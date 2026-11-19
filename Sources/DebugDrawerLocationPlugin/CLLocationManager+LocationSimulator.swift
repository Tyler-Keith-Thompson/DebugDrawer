#if DEBUG
    import CoreLocation
    import ObjectiveC
    import os

    /// The exchange of `CLLocationManager`'s location methods with the ones below, made by the
    /// Location plugin's install and put back, each method's original implementation set again,
    /// by its uninstall.
    ///
    /// While installed, `startUpdatingLocation`, `stopUpdatingLocation`, `requestLocation` and
    /// `location` ask ``LocationSimulator/shared``, and each `debugDrawer…` selector runs Core
    /// Location's original, which ``CoreLocationService`` calls. A method other code exchanged
    /// again since stays exchanged after an uninstall, and calls Core Location straight through.
    @MainActor
    enum LocationSwizzles {
        private static let replacements = MethodReplacements()

        /// Whether the exchanged methods ask the simulator. Behind a lock: the app calls them on
        /// whatever thread it likes, synchronously.
        nonisolated static var isInstalled: Bool {
            installed.withLock { $0 }
        }

        private nonisolated static let installed = OSAllocatedUnfairLock(initialState: false)

        /// Exchanges the methods; a second call changes only the ones put back since.
        static func install() {
            installed.withLock { $0 = true }
            exchange(#selector(CLLocationManager.startUpdatingLocation), #selector(CLLocationManager.debugDrawerStartUpdatingLocation))
            exchange(#selector(CLLocationManager.stopUpdatingLocation), #selector(CLLocationManager.debugDrawerStopUpdatingLocation))
            exchange(#selector(CLLocationManager.requestLocation), #selector(CLLocationManager.debugDrawerRequestLocation))
            exchange(#selector(getter: CLLocationManager.location), #selector(CLLocationManager.debugDrawerLocation))
        }

        /// Puts every method's original implementation back, except one other code exchanged
        /// again since.
        ///
        /// - Returns: How many exchanges were left in place.
        @discardableResult
        static func uninstall() -> Int {
            installed.withLock { $0 = false }
            return replacements.restore()
        }

        private static func exchange(_ original: Selector, _ replacement: Selector) {
            guard let originalMethod = class_getInstanceMethod(CLLocationManager.self, original),
                  let replacementMethod = class_getInstanceMethod(CLLocationManager.self, replacement)
            else { return }
            replacements.exchange(originalMethod, with: replacementMethod)
        }
    }

    // `init` is left alone: a manager is tracked from the moment the app starts its updates, which
    // is when it can be given locations, so nothing has to replace a method of the init family.
    // Each method runs under the original selector once exchanged, so calling its own selector
    // runs Core Location's code.
    extension CLLocationManager {
        @objc dynamic func debugDrawerStartUpdatingLocation() {
            guard LocationSwizzles.isInstalled else { return debugDrawerStartUpdatingLocation() }
            LocationSimulator.shared.startUpdatingLocation(for: self)
        }

        @objc dynamic func debugDrawerStopUpdatingLocation() {
            guard LocationSwizzles.isInstalled else { return debugDrawerStopUpdatingLocation() }
            LocationSimulator.shared.stopUpdatingLocation(for: self)
        }

        @objc dynamic func debugDrawerRequestLocation() {
            guard LocationSwizzles.isInstalled else { return debugDrawerRequestLocation() }
            LocationSimulator.shared.requestLocation(for: self)
        }

        @objc dynamic func debugDrawerLocation() -> CLLocation? {
            guard LocationSwizzles.isInstalled else { return debugDrawerLocation() }
            return LocationSimulator.shared.location(for: self)
        }
    }
#endif
