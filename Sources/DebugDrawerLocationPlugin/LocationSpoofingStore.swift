#if DEBUG
    /// Where the spoofing switch and the fixed coordinate are kept, so they outlast a relaunch.
    ///
    /// ``LocationSimulator`` reads it on every question a swizzled `CLLocationManager` method asks,
    /// on whatever thread the app asks from, so it is `Sendable`.
    protocol LocationSpoofingStore: Sendable {
        /// Whether locations are simulated; false when nothing is kept.
        var isEnabled: Bool { get nonmutating set }

        /// The fixed coordinate kept, as stored, or nil when none is. Range checks are the
        /// simulator's.
        var coordinate: LocationCoordinate? { get nonmutating set }
    }
#endif
