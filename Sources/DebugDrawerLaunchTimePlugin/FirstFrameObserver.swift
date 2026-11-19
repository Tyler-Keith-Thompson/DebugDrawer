#if DEBUG
    /// Tells the Launch Time model when the app's first frame is in.
    ///
    /// The model takes it at init; `_FirstFrameObserver` watches the main run loop, and a test
    /// passes one it fires by hand.
    @MainActor
    protocol FirstFrameObserver {
        /// Calls `handler` once the first frame is in. Calling it again while waiting does nothing.
        ///
        /// - Parameter handler: Called on the main actor; it may call ``stop()``.
        func start(_ handler: @escaping @MainActor @Sendable () -> Void)

        /// Stops waiting, if it is; `start`'s handler is then never called.
        func stop()
    }
#endif
