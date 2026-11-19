#if DEBUG
    import Foundation

    // A one-shot `Timer` on the main run loop, in the common modes so it fires while a scroll view
    // tracks: it fires on the main thread, where the sessions are, and a timer whose date passed
    // while the app was suspended fires as the app runs again. Rejected: a `DispatchSourceTimer`
    // (it fires on a queue, and the sessions would hop to the main actor anyway) and
    // `Timer.publish` (a repeating publisher for a single call).

    /// The production session timer: a one-shot timer on the main run loop.
    @MainActor
    final class RunLoopSessionTimer: SessionTimer {
        /// The scheduled timer; `nil` once cancelled.
        private(set) var timer: Timer?

        func schedule(at date: Date, _ fire: @escaping @MainActor () -> Void) {
            cancel()
            let timer = Timer(fire: date, interval: 0, repeats: false) { _ in
                // A timer added to the main run loop fires on the main thread.
                MainActor.assumeIsolated { fire() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }

        func cancel() {
            timer?.invalidate()
            timer = nil
        }
    }
#endif
