#if DEBUG
    import CoreFoundation
    import DebugDrawerHangDetector
    import Foundation

    /// A thread with a run loop of its own that runs the steps it is given in order, each in a
    /// pass of its run loop of its own, so each is one stretch a monitor of that run loop
    /// measures; with the last done, its run loop has nothing left and the thread ends.
    ///
    /// A step that stands for the app's own stall waits for `release`, which a
    /// `ReleasingSampler` over ``sampler`` signals once the watcher has captured the stack: such
    /// a stall ends because it was captured, not after a time the test picked.
    final class SteppingThread: @unchecked Sendable {
        // Unchecked: the run loop and the sampler are written once, on the thread, before `init`
        // returns, and only read after.
        let runLoop: CFRunLoop
        let sampler: MachThreadStackSampler
        private let go = DispatchSemaphore(value: 0)
        private let done = DispatchSemaphore(value: 0)

        init(steps: [@Sendable () -> Void]) {
            let ready = DispatchSemaphore(value: 0)
            let go = go
            let done = done
            nonisolated(unsafe) var runLoop: CFRunLoop?
            nonisolated(unsafe) var sampler: MachThreadStackSampler?
            let thread = Thread {
                runLoop = CFRunLoopGetCurrent()
                sampler = .currentThread()
                ready.signal()
                go.wait()
                // Each step's timer adds the next one's, due at once: a timer added while timers
                // fire waits for the next pass, which first goes past the observers that end one
                // stretch and begin another.
                func schedule(_ index: Int) {
                    guard index < steps.count else { return }
                    let timer = CFRunLoopTimerCreateWithHandler(nil, CFAbsoluteTimeGetCurrent(), 0, 0, 0) { _ in
                        steps[index]()
                        schedule(index + 1)
                    }
                    CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, .defaultMode)
                }
                schedule(0)
                CFRunLoopRun()
                done.signal()
            }
            thread.start()
            ready.wait()
            // Written before `ready` was signalled, on the thread just started.
            self.runLoop = runLoop!
            self.sampler = sampler!
        }

        /// Runs the steps.
        func run() {
            go.signal()
        }

        /// Whether the last step ran within 30 seconds of being told to run.
        func finished() -> Bool {
            done.wait(timeout: .now() + 30) == .success
        }
    }
#endif
