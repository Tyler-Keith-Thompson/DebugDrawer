#if DEBUG
    import CoreFoundation
    @testable import DebugDrawerHangDetectorPlugin
    import Foundation
    import os
    import Testing

    /// Samples the watched thread, then lets it go: the thread's stall ends because the watcher
    /// captured it, not after a time the test picked.
    private struct ReleasingSampler: StackSampler {
        let base: MachThreadStackSampler
        let release: DispatchSemaphore

        func sample(into frames: UnsafeMutableBufferPointer<UInt>) -> Int {
            let count = base.sample(into: frames)
            release.signal()
            return count
        }
    }

    @Suite(.timeLimit(.minutes(1)))
    struct HangMonitorTests {
        @Test("A run loop's thread stuck past the threshold is reported once, with how long and the stack it was stuck on")
        func detectsHang() throws {
            let threshold = Duration.milliseconds(50)
            let ready = DispatchSemaphore(value: 0)
            let start = DispatchSemaphore(value: 0)
            let release = DispatchSemaphore(value: 0)
            let done = DispatchSemaphore(value: 0)
            let hangs = OSAllocatedUnfairLock<[DetectedHang]>(initialState: [])
            nonisolated(unsafe) var runLoop: CFRunLoop?
            nonisolated(unsafe) var sampler: MachThreadStackSampler?
            // The thread's run loop waits once, then a timer it was given wakes it, and the timer
            // blocks the thread until the watcher has sampled it. With the timer gone the run
            // loop has nothing left and returns.
            let thread = Thread {
                runLoop = CFRunLoopGetCurrent()
                sampler = .currentThread()
                let timer = CFRunLoopTimerCreateWithHandler(nil, CFAbsoluteTimeGetCurrent(), 0, 0, 0) { _ in
                    _ = release.wait(timeout: .now() + 30)
                }
                CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, .defaultMode)
                ready.signal()
                start.wait()
                CFRunLoopRun()
                done.signal()
            }
            thread.start()
            ready.wait()
            let sut = HangMonitor(
                runLoop: try #require(runLoop),
                sampler: ReleasingSampler(base: try #require(sampler), release: release),
                threshold: threshold
            ) { hang in hangs.withLock { $0.append(hang) } }

            start.signal()
            let finished = done.wait(timeout: .now() + 30)
            let actual = hangs.withLock { $0 }
            let frames = Symbolicator.lines(for: try #require(actual.first).addresses)

            #expect(finished == .success)
            #expect(actual.count == 1)
            #expect(try #require(actual.first).duration >= threshold)
            #expect(frames.contains { $0.contains("dispatch_semaphore_wait") || $0.contains("DispatchSemaphore") })
            #expect(frames.contains { $0.contains("CFRunLoop") })
            withExtendedLifetime(sut) {}
        }

        @Test("The threshold can change while the monitor runs")
        func thresholdChange() throws {
            let sut = HangMonitor(
                runLoop: CFRunLoopGetCurrent(), sampler: MachThreadStackSampler.currentThread(), threshold: .milliseconds(250)
            ) { _ in }

            sut.threshold = .milliseconds(100)

            #expect(sut.threshold == .milliseconds(100))
        }
    }
#endif
