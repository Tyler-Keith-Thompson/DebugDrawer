#if DEBUG
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
#endif
