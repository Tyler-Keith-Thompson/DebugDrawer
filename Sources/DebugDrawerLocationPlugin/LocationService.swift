#if DEBUG
    import CoreLocation

    /// Core Location's own behavior for a manager: what `CLLocationManager` does when the
    /// simulator lets a call through. `CoreLocationService` in production; tests pass a fake
    /// that records the calls, so none of them reaches the Mac's location service.
    protocol LocationService: Sendable {
        /// Starts the manager's real location updates.
        func startUpdatingLocation(_ manager: CLLocationManager)

        /// Stops the manager's real location updates.
        func stopUpdatingLocation(_ manager: CLLocationManager)

        /// Asks for one real location for the manager.
        func requestLocation(_ manager: CLLocationManager)

        /// The manager's last real location, or nil.
        func location(of manager: CLLocationManager) -> CLLocation?
    }

    /// `CLLocationManager`'s original implementations, reached through the selectors the
    /// swizzles exchanged them onto (`CLLocationManager+LocationSimulator.swift`).
    ///
    /// Only a call that came through a swizzled method reaches it: the simulator calls it for a
    /// manager the app started or asked through those methods, so the exchange has happened and
    /// each `debugDrawer…` selector runs Core Location's code.
    struct CoreLocationService: LocationService {
        func startUpdatingLocation(_ manager: CLLocationManager) {
            manager.debugDrawerStartUpdatingLocation()
        }

        func stopUpdatingLocation(_ manager: CLLocationManager) {
            manager.debugDrawerStopUpdatingLocation()
        }

        func requestLocation(_ manager: CLLocationManager) {
            manager.debugDrawerRequestLocation()
        }

        func location(of manager: CLLocationManager) -> CLLocation? {
            manager.debugDrawerLocation()
        }
    }
#endif
