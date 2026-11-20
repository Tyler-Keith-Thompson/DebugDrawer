#if DEBUG
    import CoreLocation
    import ObjectiveC
    import os

    // The exchange is the process's one, so it can route to one simulator only. The drawer that
    // installed the plugin last gets the app's managers, as Network, Console and View Inspector
    // capture for theirs: a drawer of a test's own, installed while the app's drawer holds the
    // plugin too, simulates for every manager, and the app's drawer again once it is removed.
    // Rejected: the first install keeping the managers (a drawer installed later would simulate
    // nothing), only the shared drawer's simulator reaching the managers (a test drawer's install
    // would intercept nothing), and every installed simulator delivering (two locations, in no
    // order, to one manager).

    /// The exchange of `CLLocationManager`'s location methods with the ones below, made as the
    /// first drawer installs the Location plugin and put back, each method's original
    /// implementation set again, as the last removes it.
    ///
    /// While installed, `startUpdatingLocation`, `stopUpdatingLocation`, `requestLocation` and
    /// `location` ask ``simulator``: the simulator of the drawer that installed the plugin last.
    /// Each `debugDrawer…` selector runs Core Location's original, which ``CoreLocationService``
    /// calls. A method other code exchanged again since stays exchanged after an uninstall, and
    /// calls Core Location straight through.
    @MainActor
    enum LocationSwizzles {
        /// A drawer holding the plugin, with the simulator its plugin's model gives locations
        /// through.
        private struct Installation: Sendable {
            let drawer: ObjectIdentifier
            let simulator: LocationSimulator
        }

        private static let replacements = MethodReplacements()

        /// The drawers holding the plugin, in the order they installed it. Behind a lock: the app
        /// calls the exchanged methods on whatever thread it likes, synchronously.
        private nonisolated static let installations = OSAllocatedUnfairLock(initialState: [Installation]())

        /// The simulator the exchanged methods ask: the latest install's, or nil while no drawer
        /// holds the plugin, when they call Core Location straight through.
        nonisolated static var simulator: LocationSimulator? {
            installations.withLock { $0.last?.simulator }
        }

        /// Routes the app's managers to `simulator` while `drawer` is the latest to hold the
        /// plugin, handing it the managers the previous latest tracked, and exchanges the methods;
        /// a second call for `drawer` changes only the methods put back since.
        static func install(_ simulator: LocationSimulator, for drawer: ObjectIdentifier) {
            let previous = installations.withLock { installations -> LocationSimulator? in
                guard !installations.contains(where: { $0.drawer == drawer }) else { return nil }
                let previous = installations.last?.simulator
                installations.append(Installation(drawer: drawer, simulator: simulator))
                return previous
            }
            if let previous, previous !== simulator {
                previous.handOff(to: simulator)
            }
            exchange(#selector(CLLocationManager.startUpdatingLocation), #selector(CLLocationManager.debugDrawerStartUpdatingLocation))
            exchange(#selector(CLLocationManager.stopUpdatingLocation), #selector(CLLocationManager.debugDrawerStopUpdatingLocation))
            exchange(#selector(CLLocationManager.requestLocation), #selector(CLLocationManager.debugDrawerRequestLocation))
            exchange(#selector(getter: CLLocationManager.location), #selector(CLLocationManager.debugDrawerLocation))
        }

        /// Stops routing to `drawer`'s simulator. Was it the latest, the install before it gets
        /// the managers; was it the last, every manager is handed back to Core Location and every
        /// method gets its original implementation back, except one other code exchanged again
        /// since. A drawer that holds no plugin changes nothing.
        static func uninstall(for drawer: ObjectIdentifier) {
            let change = installations.withLock { installations -> (removed: LocationSimulator, next: LocationSimulator?)? in
                guard let index = installations.lastIndex(where: { $0.drawer == drawer }) else { return nil }
                let wasLatest = index == installations.index(before: installations.endIndex)
                let removed = installations.remove(at: index)
                guard wasLatest || installations.isEmpty else { return nil }
                return (removed.simulator, installations.last?.simulator)
            }
            switch change {
            case nil:
                return
            case let (removed, next?)?:
                if next !== removed { removed.handOff(to: next) }
            case let (removed, nil)?:
                // Before the methods are put back, while CoreLocationService still reaches Core
                // Location's code through the exchanged selectors.
                removed.release()
                replacements.restore()
            }
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
            guard let simulator = LocationSwizzles.simulator else { return debugDrawerStartUpdatingLocation() }
            simulator.startUpdatingLocation(for: self)
        }

        @objc dynamic func debugDrawerStopUpdatingLocation() {
            guard let simulator = LocationSwizzles.simulator else { return debugDrawerStopUpdatingLocation() }
            simulator.stopUpdatingLocation(for: self)
        }

        @objc dynamic func debugDrawerRequestLocation() {
            guard let simulator = LocationSwizzles.simulator else { return debugDrawerRequestLocation() }
            simulator.requestLocation(for: self)
        }

        @objc dynamic func debugDrawerLocation() -> CLLocation? {
            guard let simulator = LocationSwizzles.simulator else { return debugDrawerLocation() }
            return simulator.location(for: self)
        }
    }
#endif
