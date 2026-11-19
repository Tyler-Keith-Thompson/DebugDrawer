#if DEBUG
    import Foundation

    /// The system's thermal state, and word when it changes.
    ///
    /// The Energy monitor takes it at init and reads it only while it samples;
    /// `_ThermalStateReader` reads `ProcessInfo`'s, and a test passes one it sets by hand.
    @MainActor
    protocol ThermalStateReader: AnyObject {
        /// The thermal state now.
        var thermalState: ProcessInfo.ThermalState { get }

        /// Calls `change` each time the thermal state changes, until ``stopObserving()``.
        ///
        /// - Parameter change: Called on the main actor.
        func startObserving(_ change: @escaping @MainActor () -> Void)

        /// Stops calling the handler ``startObserving(_:)`` took; does nothing when not observing.
        func stopObserving()
    }
#endif
