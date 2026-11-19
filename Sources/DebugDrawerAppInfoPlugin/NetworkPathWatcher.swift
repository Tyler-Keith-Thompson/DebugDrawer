#if DEBUG
    import Foundation

    /// Reports the network's reachability as it changes, from ``start(_:)`` to ``stop()``.
    ///
    /// The App Info model takes it at init; `NWPathNetworkWatcher` watches the system's path, and
    /// a test passes a fake that records when it starts and stops.
    @MainActor
    protocol NetworkPathWatcher: AnyObject {
        /// Starts watching; `update` gets the status now and after each change, on any thread.
        func start(_ update: @escaping @Sendable (NetworkReachability) -> Void)

        /// Stops watching; does nothing when stopped.
        func stop()
    }
#endif
