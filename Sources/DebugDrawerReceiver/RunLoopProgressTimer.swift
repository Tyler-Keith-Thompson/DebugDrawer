import Foundation

// A repeating `Timer` on the main run loop, in the common modes, as `RunLoopSessionTimer` is: it
// fires on the main thread, where the keeper is, and keeps firing while the app runs in the
// background under its continued processing task. Rejected: `Timer.publish` (a Combine
// subscription to hold for what is a start and a stop) and a `DispatchSourceTimer` (a queue hop
// back to the main actor on every tick).

/// The production progress timer: a repeating timer on the main run loop.
@MainActor
final class RunLoopProgressTimer: ProgressTimer {
    private var timer: Timer?

    func start(every interval: TimeInterval, _ tick: @escaping @MainActor () -> Void) {
        stop()
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            // A timer added to the main run loop fires on the main thread.
            MainActor.assumeIsolated { tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
