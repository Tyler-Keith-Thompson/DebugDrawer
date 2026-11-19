#if DEBUG
    import CoreLocation

    /// What the app's location managers are given in place of Core Location's fixes: the spoofing
    /// switch, the fixed coordinate and a route's latest point. ``LocationSimulator`` in production,
    /// which the swizzled `CLLocationManager` methods ask; tests pass a fake that records what it
    /// was told.
    @MainActor
    protocol LocationOverride: AnyObject {
        /// Whether locations are simulated.
        var isEnabled: Bool { get set }

        /// The fixed location given while no route plays, or nil for none. Setting one out of
        /// range (`CLLocationCoordinate2DIsValid`) traps.
        var coordinate: CLLocationCoordinate2D? { get set }

        /// The location managers are given now: the route's latest point while one plays, else the
        /// fixed coordinate, while spoofing is on; nil while none is.
        var simulatedLocation: CLLocation? { get }

        /// Gives every updating manager a route's next point, and keeps it in effect until the next.
        func deliverRoute(_ location: CLLocation)

        /// Ends a route: the fixed coordinate, if one is set, is in effect again.
        func endRoute()

        /// Lets go of every manager, handing each back to Core Location, and forgets the route's
        /// point. The switch and the coordinate stay.
        func release()
    }
#endif
