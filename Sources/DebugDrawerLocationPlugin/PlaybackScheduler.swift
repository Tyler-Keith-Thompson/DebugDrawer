#if DEBUG
    import Combine
    import Foundation

    /// The clock route playback runs on: the time now, and work run once after a delay. Tests pass
    /// a fake they advance by hand.
    @MainActor
    protocol PlaybackScheduler: AnyObject {
        /// The time now, which stamps each location delivered.
        var now: Date { get }

        /// Runs `action` on the main actor once `delay` has passed, unless the returned value is
        /// cancelled or released first.
        ///
        /// - Parameters:
        ///   - delay: Seconds from now; zero or less runs it at the next turn of the run loop.
        ///   - action: The work to run.
        func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> AnyCancellable
    }

    /// The production clock: the system's time, and a one-shot Combine timer on the main run loop.
    @MainActor
    final class TimerPlaybackScheduler: PlaybackScheduler {
        var now: Date { Date() }

        func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> AnyCancellable {
            // `.common`, so a route keeps playing while a scroll view tracks a drag. A timer given a
            // delay of zero or less fires after 0.1 ms, as Foundation's Timer documents.
            Timer.publish(every: delay, on: .main, in: .common)
                .autoconnect()
                .first()
                .sink { _ in
                    // The main run loop runs the timer, so this is on the main thread.
                    MainActor.assumeIsolated { action() }
                }
        }
    }
#endif
