#if DEBUG
    /// Whether Low Power Mode is on, and word when it changes.
    ///
    /// The Energy monitor takes it at init and reads it only while it samples;
    /// `_LowPowerModeReader` reads `ProcessInfo`'s, and a test passes one it sets by hand.
    @MainActor
    protocol LowPowerModeReader: AnyObject {
        /// Whether Low Power Mode is on now.
        var isLowPowerModeEnabled: Bool { get }

        /// Calls `change` each time Low Power Mode turns on or off, until ``stopObserving()``.
        ///
        /// - Parameter change: Called on the main actor.
        func startObserving(_ change: @escaping @MainActor () -> Void)

        /// Stops calling the handler ``startObserving(_:)`` took; does nothing when not observing.
        func stopObserving()
    }
#endif
