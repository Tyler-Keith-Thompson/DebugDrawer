// What watching the main thread costs when it never hangs. The detector exists in debug builds
// only, so it is measured there; `--config=release` builds this target without it, and runs
// ReleaseInstallTests instead.
#if DEBUG
    import CoreFoundation
    @testable import DebugDrawerHangDetectorPlugin
    import Foundation
    import Testing

    // Measured on an Apple silicon Mac in debug builds (`bazel test`, `swift test`), no stalls:
    // - a checkpoint (the observer's work: the clock, the lock, the tracker) 0.29 to 0.33 µs;
    // - a turn of a run loop that waits and is woken (four checkpoints) about 0.65 µs without
    //   the observers and 0.8 to 1.4 µs more with them;
    // - a watcher wake 0.27 to 0.45 µs of work besides the kernel's wake, four times per
    //   threshold (16 a second at 250 ms), so well under 0.01 ms of CPU a second.
    // The bounds below are several times those figures, so a loaded machine passes and a change
    // that makes the observer do real work (allocate, log, symbolicate) fails.
    @Suite(.timeLimit(.minutes(1)))
    struct HangDetectorOverheadTests {
        @Test("A checkpoint with no hang costs under 2 µs")
        func checkpointCost() {
            let sut = HangMonitorState(threshold: .milliseconds(250))
            let iterations = 500_000
            let clock = ContinuousClock()

            let elapsed = clock.measure {
                for _ in 0 ..< iterations {
                    _ = sut.checkpoint(isAboutToWait: false)
                    _ = sut.checkpoint(isAboutToWait: true)
                }
            }
            let actual = elapsed / (iterations * 2)

            print("Hang detector: a checkpoint costs \(actual)")
            #expect(actual < .microseconds(2))
        }

        @Test("A watcher wake with the thread idle costs under 5 µs")
        func tickCost() {
            let sut = HangMonitorState(threshold: .milliseconds(250))
            _ = sut.checkpoint(isAboutToWait: true)
            let sampler = MachThreadStackSampler.currentThread()
            let iterations = 200_000
            let clock = ContinuousClock()

            let elapsed = clock.measure {
                for _ in 0 ..< iterations {
                    sut.tick(sampler)
                }
            }
            let actual = elapsed / iterations

            print("Hang detector: a watcher wake costs \(actual)")
            #expect(actual < .microseconds(5))
        }

        @Test("The observers add under 10 µs to a turn of a run loop that waits and is woken")
        func runLoopTurnCost() throws {
            let turns = 50_000

            let without = try Self.timeTurns(turns, watched: false)
            let with = try Self.timeTurns(turns, watched: true)
            let actual = (with - without) / turns

            print("Hang detector: a run loop turn takes \(without / turns) unwatched, \(with / turns) watched, \(actual) more")
            #expect(actual < .microseconds(10))
        }

        /// How long `turns` turns of a fresh thread's run loop take, each a block that schedules
        /// the next and wakes the loop, so every turn waits and wakes as an app's does.
        private static func timeTurns(_ turns: Int, watched: Bool) throws -> Duration {
            let ready = DispatchSemaphore(value: 0)
            let start = DispatchSemaphore(value: 0)
            let done = DispatchSemaphore(value: 0)
            nonisolated(unsafe) var runLoop: CFRunLoop?
            nonisolated(unsafe) var sampler: MachThreadStackSampler?
            nonisolated(unsafe) var elapsed = Duration.zero
            let thread = Thread {
                let current = CFRunLoopGetCurrent()
                runLoop = current
                sampler = .currentThread()
                // Keeps the run loop running between blocks, which aren't sources.
                let keepAlive = CFRunLoopTimerCreateWithHandler(nil, .greatestFiniteMagnitude, 0, 0, 0) { _ in }
                CFRunLoopAddTimer(current, keepAlive, .defaultMode)
                nonisolated(unsafe) var remaining = turns
                nonisolated(unsafe) var turn: (() -> Void)?
                turn = {
                    remaining -= 1
                    if remaining == 0 {
                        CFRunLoopStop(current)
                    } else {
                        CFRunLoopPerformBlock(current, CFRunLoopMode.defaultMode.rawValue, turn)
                        CFRunLoopWakeUp(current)
                    }
                }
                CFRunLoopPerformBlock(current, CFRunLoopMode.defaultMode.rawValue, turn)
                ready.signal()
                start.wait()
                elapsed = ContinuousClock().measure { CFRunLoopRun() }
                turn = nil
                done.signal()
            }
            thread.start()
            ready.wait()
            let monitor = watched
                ? HangMonitor(runLoop: try #require(runLoop), sampler: try #require(sampler), threshold: .milliseconds(250)) { _ in }
                : nil
            start.signal()
            done.wait()
            withExtendedLifetime(monitor) {}
            return elapsed
        }
    }
#endif
