// The leak detector measured here exists only in debug builds of the library (`#if DEBUG`), and a
// release build of it has no-op stand-ins, which would measure nothing. `just bench` builds
// optimized with DEBUG defined; this stops any other build from passing for a measurement.
#if !DEBUG
    #error("Build the benchmarks with `just bench`, which defines DEBUG: the leak detector they measure is DEBUG-only.")
#endif

// What the leak detector adds to each turn of the main run loop, through the public install: its
// observer checks at every turn's end whether a view controller dismissed in an earlier turn is
// still alive, and while one is flagged it rechecks it each turn.
import AppKit
import Benchmark
import DebugDrawer
import DebugDrawerLeakDetectorPlugin
import Foundation
import ObjectiveC

/// A screen of the app's own (this executable's class, which the detector watches).
final class Screen: NSViewController {}

/// The view controllers the flagged benchmark dismissed and keeps alive.
@MainActor var flagged: [Screen] = []

/// Installs the plugin, which exchanges `viewDidDisappear` and observes the main run loop's turns,
/// and traps unless the exchange took.
@MainActor func install() {
    let disappear = #selector(NSViewController.viewDidDisappear)
    let original = class_getInstanceMethod(NSViewController.self, disappear).map(method_getImplementation)
    LeakDetector.install()
    guard class_getInstanceMethod(NSViewController.self, disappear).map(method_getImplementation) != original else {
        fatalError("LeakDetector.install() didn't exchange NSViewController.viewDidDisappear")
    }
}

// The same as the HangDetector target's; each target stands alone.
/// Turns the main run loop `turns` times, each turn a block that schedules the next and wakes the
/// loop, so every turn ends by waiting, where the detector's observer runs, and is woken as an
/// app's is. Runs the loop nested in the main actor's job, which it returns to.
@MainActor func turnMainRunLoop(_ turns: Int) {
    let runLoop = CFRunLoopGetMain()!
    nonisolated(unsafe) var remaining = turns
    nonisolated(unsafe) var turn: (() -> Void)?
    turn = {
        remaining -= 1
        if remaining == 0 {
            CFRunLoopStop(runLoop)
        } else {
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue, turn)
            CFRunLoopWakeUp(runLoop)
        }
    }
    CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue, turn)
    CFRunLoopRun()
    turn = nil
}

/// Keeps the main run loop's default mode from being empty, so a nested run waits for the next
/// block rather than returning; added once, by each benchmark's setup.
@MainActor func keepMainRunLoopAlive() {
    let keepAlive = CFRunLoopTimerCreateWithHandler(nil, .greatestFiniteMagnitude, 0, 0, 0) { _ in }
    CFRunLoopAddTimer(CFRunLoopGetMain(), keepAlive, .defaultMode)
}

let benchmarks: @Sendable () -> Void = {
    // Each benchmark runs in a process of its own, so one benchmark's install never reaches another.
    // Gated (just bench-check) at 10% over the main baseline's median: the process's retired
    // instructions and its mallocs; reported only: wall clock and CPU time, which move with
    // whatever else the Mac is doing. A thousand turns an iteration, reported per turn; a fixed
    // number of iterations.
    Benchmark.defaultConfiguration = .init(
        metrics: [.wallClock, .cpuTotal, .instructions, .mallocCountTotal],
        warmupIterations: 3,
        scalingFactor: .kilo,
        maxDuration: .seconds(120),
        maxIterations: 50,
        thresholds: [
            .instructions: .init(relative: [.p50: 10.0]),
            .mallocCountTotal: .init(relative: [.p50: 10.0]),
            // Reported, not gated.
            .wallClock: .init(),
            .cpuTotal: .init()
        ]
    )

    // A main run loop turn that waits and is woken, which installing must keep pace with.
    Benchmark(
        "LeakDetector: BASELINE main run loop turn, not installed",
        configuration: .init(setup: { await MainActor.run { keepMainRunLoopAlive() } })
    ) { benchmark in
        let turns = benchmark.scaledIterations.count
        await MainActor.run { turnMainRunLoop(turns) }
    }

    // The same turn installed, with nothing dismissed: what most of an app's turns cost.
    Benchmark(
        "LeakDetector: main run loop turn, nothing dismissed, installed",
        configuration: .init(setup: {
            await MainActor.run {
                keepMainRunLoopAlive()
                install()
            }
        })
    ) { benchmark in
        let turns = benchmark.scaledIterations.count
        await MainActor.run { turnMainRunLoop(turns) }
    }

    // The same turn with ten dismissed view controllers still alive: flagged at the first turn's
    // end, and rechecked at every turn after it.
    Benchmark(
        "LeakDetector: main run loop turn, ten flagged view controllers, installed",
        configuration: .init(setup: {
            await MainActor.run {
                keepMainRunLoopAlive()
                install()
                flagged = (0 ..< 10).map { _ in Screen() }
                // Never shown, so off screen for good once it disappears.
                for screen in flagged {
                    screen.viewDidDisappear()
                }
                turnMainRunLoop(2)
            }
        })
    ) { benchmark in
        let turns = benchmark.scaledIterations.count
        await MainActor.run { turnMainRunLoop(turns) }
    }
}
