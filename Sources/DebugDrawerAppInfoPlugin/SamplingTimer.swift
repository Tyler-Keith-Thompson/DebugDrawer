#if DEBUG
    import Combine
    import Foundation

    /// Calls back at a fixed interval while App Info's metrics refresh. Tests pass a fake that
    /// records when it starts and stops.
    @MainActor
    protocol SamplingTimer: AnyObject {
        /// Starts calling `tick` at the timer's interval, until ``stop()``.
        func start(_ tick: @escaping @MainActor () -> Void)

        /// Stops the ticks; does nothing when stopped.
        func stop()
    }

    /// The production timer: a timer on the main run loop, so every tick runs on the main actor.
    /// Energy has a timer of its own: plugins share no helper target.
    @MainActor
    final class RunLoopSamplingTimer: SamplingTimer {
        /// The seconds between ticks.
        let interval: TimeInterval
        /// The timer's subscription while it ticks; `nil` once stopped.
        private(set) var cancellable: AnyCancellable?

        /// - Parameter interval: The seconds between ticks.
        init(interval: TimeInterval) {
            self.interval = interval
        }

        func start(_ tick: @escaping @MainActor () -> Void) {
            cancellable = Timer.publish(every: interval, on: .main, in: .common)
                .autoconnect()
                .sink { _ in tick() }
        }

        func stop() {
            cancellable?.cancel()
            cancellable = nil
        }
    }
#endif
