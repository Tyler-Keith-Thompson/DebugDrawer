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

/// Points stdout at /dev/null, so no benchmark writes to the terminal. The `Logger` benchmarks
/// install with stdout there; the stdout ones lead it into a pipe of their own first
/// (`echoReadingEnd`).
@Sendable func silenceStandardOutput() async throws {
    let null = open("/dev/null", O_WRONLY)
    guard null >= 0, dup2(null, STDOUT_FILENO) >= 0 else {
        fatalError("stdout couldn't be pointed at /dev/null")
    }
    close(null)
}

/// The reading end of a pipe of the benchmark's own that stdout leads into. The `FileHandle` and
/// `print` benchmarks read each line back out of it before they write the next, in both arms.
/// Made the first time it's read, from the first (warmup) iteration: the runner points stdout at
/// /dev/null between setup and the first iteration. Installing afterwards makes this pipe the
/// place the plugin forwards captured output to, as a terminal or Xcode's console is in an app.
/// C's stdout buffers fully once it finds a pipe behind it; line buffering makes each `print` one
/// write, as the plugin's install does in the installed arm.
let echoReadingEnd: Int32 = {
    var ends: [Int32] = [-1, -1]
    guard pipe(&ends) == 0, dup2(ends[1], STDOUT_FILENO) >= 0 else {
        fatalError("stdout couldn't be pointed at the benchmark's pipe")
    }
    close(ends[1])
    setvbuf(stdout, nil, _IOLBF, 0)
    return ends[0]
}()

/// Returns once `count` bytes, the line just written to stdout, came out of the benchmark's pipe:
/// in the installed arm, once the plugin's reader has read that line and forwarded it. A blocking
/// read, which holds up nothing the plugin needs: its reader runs on a dispatch queue of its own.
func awaitEcho(of count: Int) {
    withUnsafeTemporaryAllocation(byteCount: count, alignment: 1) { buffer in
        // A temporary allocation of a nonzero count always has a base address.
        let start = buffer.baseAddress!
        var received = 0
        while received < count {
            let readCount = read(echoReadingEnd, start + received, count - received)
            guard readCount > 0 else {
                fatalError("The benchmark's stdout pipe ended or failed (errno \(errno))")
            }
            received += readCount
        }
    }
}

/// Whether this process has installed the plugin.
let isInstalled = Atomic<Bool>(false)

/// Installs the plugin the first time it's called, checks stdout then leads into a pipe of the
/// plugin's (the benchmark's own may have been there before), and returns once it reads the log
/// store. The benchmarks call it from their first (warmup) iteration rather than from setup: with
/// `--no-progress` the runner points stdout at /dev/null between setup and the first iteration,
/// which would undo the plugin's redirect.
func installOnce() async {
    guard !isInstalled.exchange(true, ordering: .relaxed) else { return }
    var before = stat()
    _ = fstat(STDOUT_FILENO, &before)
    await MainActor.run { DebugDrawer.shared.installConsole(sessions: .off) }
    var status = stat()
    guard fstat(STDOUT_FILENO, &status) == 0, status.st_mode & S_IFMT == S_IFIFO, status.st_ino != before.st_ino else {
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
    // A thousand lines an iteration, reported per line.
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

        // The stdout arms measure a line from its write until it comes out where stdout led before
        // the install. Not installed: the write into the benchmark's pipe and the read back out of
        // it. Installed: the same, plus the plugin's part between them, on the writing thread and
        // its reader's: the plugin's pipe, the reader's read, the forward, the line made for the
        // store and the task that hands it to the main actor. The store's own share on the main
        // actor (ingesting the line, and the batch it publishes every 100 ms) is left out: the
        // loop holds the main actor and stops the count before giving it up, so that work runs
        // between iterations.
        // Why the count repeats: each line is read back before the next is written, so the
        // reader reads exactly one line a read, the same every run, and every read lands inside
        // the iteration that wrote it. Without the wait it read whatever the pipe held when it got
        // its turn, one line or hundreds; a read costs mostly per read, not per byte, so the
        // median moved by up to 40% from run to run. The plugin forwards a read last, after
        // handing its lines on, so when a line comes out the reader is done with it and goes back
        // to waiting before the next is written: two context switches a line (the writer waiting
        // for its line, the reader waiting for the next), every line. With the forward first, the
        // reader was sometimes still busy when the next line came and took it without waiting,
        // about a fifth fewer instructions a line, and a run's median fell on either side. Likewise, the
        // main actor ingested lines whenever it woke, one or many a wake, and the 100 ms batch
        // fell in whichever iteration was running, so counting its share would tie the count to
        // scheduling again.
        Benchmark("\(prefix) FileHandle.standardOutput.write, one line, \(arm)") { @MainActor benchmark in
            _ = echoReadingEnd
            if installed {
                await installOnce()
            }
            benchmark.startMeasurement()
            for _ in benchmark.scaledIterations {
                FileHandle.standardOutput.write(lineData)
                awaitEcho(of: lineData.count)
            }
            benchmark.stopMeasurement()
        }

        Benchmark("\(prefix) print, one line, \(arm)") { @MainActor benchmark in
            _ = echoReadingEnd
            if installed {
                await installOnce()
            }
            benchmark.startMeasurement()
            for _ in benchmark.scaledIterations {
                print(line)
                awaitEcho(of: lineData.count)
            }
            benchmark.stopMeasurement()
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
