#if DEBUG
    import CoreLocation
    import ObjectiveC

    /// The exchange of `CLLocationManager`'s location methods with the ones below, made once per
    /// process by `installLocation()`: a second exchange would put the originals back.
    ///
    /// After it, `startUpdatingLocation`, `stopUpdatingLocation`, `requestLocation` and
    /// `location` ask ``LocationSimulator/shared``, and each `debugDrawer…` selector runs Core
    /// Location's original, which ``CoreLocationService`` calls.
    enum LocationSwizzles {
        static let installed: Void = {
            exchange(#selector(CLLocationManager.startUpdatingLocation), #selector(CLLocationManager.debugDrawerStartUpdatingLocation))
            exchange(#selector(CLLocationManager.stopUpdatingLocation), #selector(CLLocationManager.debugDrawerStopUpdatingLocation))
            exchange(#selector(CLLocationManager.requestLocation), #selector(CLLocationManager.debugDrawerRequestLocation))
            exchange(#selector(getter: CLLocationManager.location), #selector(CLLocationManager.debugDrawerLocation))
        }()

        private static func exchange(_ original: Selector, _ replacement: Selector) {
            guard let originalMethod = class_getInstanceMethod(CLLocationManager.self, original),
                  let replacementMethod = class_getInstanceMethod(CLLocationManager.self, replacement)
            else { return }
            method_exchangeImplementations(originalMethod, replacementMethod)
        }
    }

    // `init` is left alone: a manager is tracked from the moment the app starts its updates, which
    // is when it can be given locations, so nothing has to replace a method of the init family.
    extension CLLocationManager {
        @objc dynamic func debugDrawerStartUpdatingLocation() {
            LocationSimulator.shared.startUpdatingLocation(for: self)
        }

        @objc dynamic func debugDrawerStopUpdatingLocation() {
            LocationSimulator.shared.stopUpdatingLocation(for: self)
        }

        @objc dynamic func debugDrawerRequestLocation() {
            LocationSimulator.shared.requestLocation(for: self)
        }

        @objc dynamic func debugDrawerLocation() -> CLLocation? {
            LocationSimulator.shared.location(for: self)
        }
    }
#endif
