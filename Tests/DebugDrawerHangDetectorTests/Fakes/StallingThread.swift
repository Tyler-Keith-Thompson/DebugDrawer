#if DEBUG
    import CoreFoundation
    import DebugDrawerHangDetector
    import Foundation

    /// Samples the watched thread, then lets it go: the thread's stall ends because the watcher
    /// captured it, not after a time the test picked.
    struct ReleasingSampler: StackSampler {
        let base: MachThreadStackSampler
        let release: DispatchSemaphore

        func sample(into frames: UnsafeMutableBufferPointer<UInt>) -> Int {
            let count = base.sample(into: frames)
            release.signal()
            return count
        }
    }

    /// A thread with a run loop of its own, to hand a recording as the thread it watches in place
    /// of the main one, which a test runner's main thread doesn't turn. Once told to stall, its run
    /// loop waits once, then a timer blocks it until the watcher has sampled its stack; with the
    /// timer gone the run loop has nothing left and the thread ends.
    final class StallingThread: @unchecked Sendable {
        // Unchecked: the run loop and the sampler are written once, on the thread, before `init`
        // returns, and only read after.
        let runLoop: CFRunLoop
        let sampler: ReleasingSampler
        private let go = DispatchSemaphore(value: 0)
        private let done = DispatchSemaphore(value: 0)

        init() {
            let ready = DispatchSemaphore(value: 0)
            let release = DispatchSemaphore(value: 0)
            let go = go
            let done = done
            nonisolated(unsafe) var runLoop: CFRunLoop?
            nonisolated(unsafe) var sampler: MachThreadStackSampler?
            let thread = Thread {
                runLoop = CFRunLoopGetCurrent()
                sampler = .currentThread()
                let timer = CFRunLoopTimerCreateWithHandler(nil, CFAbsoluteTimeGetCurrent(), 0, 0, 0) { _ in
                    _ = release.wait(timeout: .now() + 30)
                }
                ready.signal()
                go.wait()
                CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, .defaultMode)
                CFRunLoopRun()
                done.signal()
            }
            thread.start()
            ready.wait()
            // Written before `ready` was signalled, on the thread just started.
            self.runLoop = runLoop!
            self.sampler = ReleasingSampler(base: sampler!, release: release)
        }

        /// Turns the thread's run loop, which stalls once and then ends.
        func stall() {
            go.signal()
        }

        /// Whether the thread's run loop ended within 30 seconds of being told to stall.
        func finished() -> Bool {
            done.wait(timeout: .now() + 30) == .success
        }
    }
#endif
