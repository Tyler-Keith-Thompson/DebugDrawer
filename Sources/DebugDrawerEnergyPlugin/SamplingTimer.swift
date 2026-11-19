#if DEBUG
    /// Calls back once a second while the Energy monitor samples. Tests pass a fake that records
    /// when it starts and stops.
    @MainActor
    protocol SamplingTimer: AnyObject {
        /// Starts calling `tick` once a second, until ``stop()``.
        func start(_ tick: @escaping @MainActor () -> Void)

        /// Stops the ticks; does nothing when stopped.
        func stop()
    }
#endif
