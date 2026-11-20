// What recording performance traces costs the app while a sidecar's session records, measured in
// the build an app ships: `just test-release` (`--config=release`) builds and runs this target
// optimized, without DEBUG, and so does `just test` in debug. Each test prints what it measured;
// `PerformanceTraces`' documentation and the README quote the release figures. The bounds are
// several times those figures, so a loaded machine passes and a change that makes the observer or
// a signpost do real work (allocate, log, symbolicate) fails.
import CoreFoundation
import DebugDrawerHangDetector
import DebugDrawerReceiver
import Foundation
import Testing

@Suite(.serialized, .timeLimit(.minutes(1)))
struct PerformanceTracesOverheadTests {
    @Test("A checkpoint with no stall costs under 2 µs")
    func checkpointCost() {
        let sut = HangMonitorState(threshold: PerformanceTraces.defaultHitchThreshold)
        let iterations = 500_000
        let clock = ContinuousClock()

        let elapsed = clock.measure {
            for _ in 0 ..< iterations {
                _ = sut.checkpoint(isAboutToWait: false)
                _ = sut.checkpoint(isAboutToWait: true)
            }
        }
        let actual = elapsed / (iterations * 2)

        print("Performance traces: a checkpoint costs \(actual)")
        #expect(actual < .microseconds(2))
    }

    @Test("A watcher wake with the thread idle costs under 5 µs")
    func tickCost() {
        let sut = HangMonitorState(threshold: PerformanceTraces.defaultHitchThreshold)
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

        print("Performance traces: a watcher wake costs \(actual), \(HangTracker.ticksPerThreshold * 10) wakes a second by default")
        #expect(actual < .microseconds(5))
    }

    @Test("The observers add under 10 µs to a turn of a run loop that waits and is woken")
    func runLoopTurnCost() throws {
        let turns = 50_000

        let without = try Self.timeTurns(turns, watched: false)
        let with = try Self.timeTurns(turns, watched: true)
        let actual = (with - without) / turns

        print("Performance traces: a run loop turn takes \(without / turns) unwatched, \(with / turns) watched, \(actual) more")
        #expect(actual < .microseconds(10))
    }

    @Test("Sampling a stopped thread's stack costs under 1 ms")
    func sampleCost() throws {
        let ready = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let done = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var sampler: MachThreadStackSampler?
        let thread = Thread {
            sampler = .currentThread()
            ready.signal()
            _ = release.wait(timeout: .now() + 30)
            done.signal()
        }
        thread.start()
        ready.wait()
        let sut = try #require(sampler)
        let frames = UnsafeMutableBufferPointer<UInt>.allocate(capacity: HangMonitorState.maximumFrames)
        defer { frames.deallocate() }
        let iterations = 1000
        let clock = ContinuousClock()

        let elapsed = clock.measure {
            for _ in 0 ..< iterations {
                _ = sut.sample(into: frames)
            }
        }
        release.signal()
        done.wait()
        let actual = elapsed / iterations

        print("Performance traces: sampling a thread's stack stops it for \(actual)")
        #expect(actual < .milliseconds(1))
    }

    @Test("Naming a stack's frames costs under 50 µs a frame")
    func symbolicationCost() {
        let addresses = Thread.callStackReturnAddresses.map { UInt(truncating: $0) }
        let iterations = 200
        let clock = ContinuousClock()

        let elapsed = clock.measure {
            for _ in 0 ..< iterations {
                _ = Symbolicator.frames(for: addresses)
            }
        }
        let actual = elapsed / (iterations * max(addresses.count, 1))

        print("Performance traces: naming a frame costs \(actual), \(addresses.count) frames")
        #expect(actual < .microseconds(50))
    }

    @MainActor
    @Test("A signpost interval costs under 5 µs while recording and under 1 µs while nothing records")
    func signpostCost() {
        let sessions = DebugDrawerSessions(maximumDuration: 300)
        let sut = PerformanceTraces(sessions: sessions, limits: PerformanceTraces.Limits(stalls: 1, intervals: 100))
        let iterations = 200_000
        let clock = ContinuousClock()

        let idle = clock.measure {
            for _ in 0 ..< iterations {
                sut.endInterval(sut.beginInterval("Overhead"))
            }
        }
        sessions.perform(.open(duration: 60))
        sut.perform(.start)
        let recording = clock.measure {
            for _ in 0 ..< iterations {
                sut.endInterval(sut.beginInterval("Overhead"))
            }
        }
        sut.perform(.stop)
        sessions.end()

        print("Performance traces: a signpost interval costs \(idle / iterations) while nothing records, \(recording / iterations) while recording")
        #expect(idle / iterations < .microseconds(1))
        #expect(recording / iterations < .microseconds(5))
    }

    /// How long `turns` turns of a fresh thread's run loop take, each a block that schedules the
    /// next and wakes the loop, so every turn waits and wakes as an app's does.
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
            ? HangMonitor(
                runLoop: try #require(runLoop), sampler: try #require(sampler), threshold: PerformanceTraces.defaultHitchThreshold
            ) { _ in }
            : nil
        start.signal()
        done.wait()
        withExtendedLifetime(monitor) {}
        return elapsed
    }
}
