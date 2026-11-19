#if DEBUG
    /// The battery: its charge, whether it is charging and what powers the device, and word when
    /// any of them changes.
    ///
    /// The Energy monitor takes it at init and reads it only while it samples; `_BatteryReader`
    /// reads the system's, and a test passes one it sets by hand.
    @MainActor
    protocol BatteryReader: AnyObject {
        /// The battery now.
        func read() -> BatteryReading

        /// Calls `change` each time the system says the battery changed, until ``stopObserving()``.
        ///
        /// - Parameter change: Called on the main actor.
        func startObserving(_ change: @escaping @MainActor () -> Void)

        /// Stops calling the handler ``startObserving(_:)`` took; does nothing when not observing.
        func stopObserving()
    }
#endif
