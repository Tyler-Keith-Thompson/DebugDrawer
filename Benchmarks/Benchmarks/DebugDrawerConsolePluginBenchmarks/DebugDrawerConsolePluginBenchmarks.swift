// The interception measured here exists only in debug builds of the library (`#if DEBUG`), and a
// release build of it has no-op stand-ins, which would measure nothing. `just bench` builds
// optimized with DEBUG defined; this stops any other build from passing for a measurement.
#if !DEBUG
    #error("Build the benchmarks with `just bench`, which defines DEBUG: the interception they measure is DEBUG-only.")
#endif

import Benchmark
import DebugDrawer
import DebugDrawerConsolePlugin
import Foundation
import os
import OSLogClient
import Synchronization

/// A line as an app logs one.
let line = "[FeedLoader] Loaded 25 items for section \"Home\" in 0.142 s (cache: miss, page 3)"
let lineData = Data((line + "\n").utf8)
let logger = Logger(subsystem: "com.debugdrawer.benchmarks", category: "Console")

/// Points stdout at /dev/null, so neither arm writes to the terminal. Installing afterwards makes
/// /dev/null the place the plugin forwards captured output to, as a terminal or Xcode's console is
/// in an app.
@Sendable func silenceStandardOutput() async throws {
    let null = open("/dev/null", O_WRONLY)
    guard null >= 0, dup2(null, STDOUT_FILENO) >= 0 else {
        fatalError("stdout couldn't be pointed at /dev/null")
    }
    close(null)
}

/// Whether this process has installed the plugin.
let isInstalled = Atomic<Bool>(false)

/// Installs the plugin the first time it's called, checks stdout then leads into its pipe, and
/// returns once it reads the log store. The benchmarks call it from their first (warmup) iteration
/// rather than from setup: with `--no-progress` the runner points stdout at /dev/null between setup
/// and the first iteration, which would undo the plugin's redirect.
func installOnce() async {
    guard !isInstalled.exchange(true, ordering: .relaxed) else { return }
    await MainActor.run { DebugDrawer.shared.installConsole(sessions: .off) }
    var status = stat()
    guard fstat(STDOUT_FILENO, &status) == 0, status.st_mode & S_IFMT == S_IFIFO else {
        fatalError("installConsole() didn't redirect stdout into its pipe")
    }
    // `installConsole()` starts the log-store reader on a task of its own and announces nothing
    // when it's ready, so this checks again after each turn of the other tasks, not after a delay.
    while await !OSLogClient.isInitialized {
        await Task.yield()
    }
    while await !OSLogClient.isDriverRegistered(withId: "com.debugdrawer.console") {
        await Task.yield()
    }
}

let benchmarks: @Sendable () -> Void = {
    // Each benchmark runs in a process of its own, so one benchmark's install never reaches another.
    // Gated (just bench-check) at 10% over the main baseline's median: the process's retired
    // instructions and its mallocs, which repeat from run to run within a few percent;
    // reported only: wall clock and CPU time, which move with whatever else the Mac is doing.
    // A thousand lines an iteration, so the capture's reads, which take what the pipe holds, are
    // spread evenly over the iterations.
    // A fixed number of iterations, each run, rather than as many as fit in a time: the installed
    // arms keep what each call leaves behind, so a run's medians depend on how many calls it made.
    Benchmark.defaultConfiguration = .init(
        metrics: [.wallClock, .cpuTotal, .instructions, .mallocCountTotal],
        warmupIterations: 3,
        scalingFactor: .kilo,
        maxDuration: .seconds(120),
        maxIterations: 1_000,
        thresholds: [
            .instructions: .init(relative: [.p50: 10.0]),
            .mallocCountTotal: .init(relative: [.p50: 10.0]),
            // Reported, not gated.
            .wallClock: .init(),
            .cpuTotal: .init()
        ],
        setup: silenceStandardOutput
    )

    for installed in [false, true] {
        let arm = installed ? "installed" : "not installed"
        // The not-installed call is the BASELINE: what installing must keep pace with.
        let prefix = installed ? "Console:" : "Console: BASELINE"

        Benchmark("\(prefix) FileHandle.standardOutput.write, one line, \(arm)") { benchmark in
            if installed {
                await installOnce()
            }
            benchmark.startMeasurement()
            for _ in benchmark.scaledIterations {
                FileHandle.standardOutput.write(lineData)
            }
        }

        Benchmark("\(prefix) print, one line, \(arm)") { benchmark in
            if installed {
                await installOnce()
            }
            benchmark.startMeasurement()
            for _ in benchmark.scaledIterations {
                print(line)
            }
        }

        // os_log calls aren't intercepted: the plugin reads the process's log store every two
        // seconds (OSLogClient) and hands each new entry to the console. So the installed arm ends
        // each iteration with that read, forced, which takes in the iteration's thousand lines. A
        // read takes seconds of wall clock, so the pair runs few iterations, which also keeps the
        // lines it adds to the system's log few.
        Benchmark(
            "\(prefix) Logger.notice, one line, \(arm)",
            configuration: .init(warmupIterations: 1, maxIterations: 10)
        ) { benchmark in
            if installed {
                await installOnce()
            }
            benchmark.startMeasurement()
            for _ in benchmark.scaledIterations {
                logger.notice("[FeedLoader] Loaded \(25) items for section \("Home", privacy: .public)")
            }
            if installed {
                await OSLogClient.pollImmediately()
            }
        }
    }
}
