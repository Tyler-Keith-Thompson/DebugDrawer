#if DEBUG
    import CoreLocation
    import DebugDrawer
    import Foundation
    import os

    /// What the app's location managers are given: the switch and fixed coordinate, kept across
    /// launches, a route's latest point while one plays, and the managers that asked for updates.
    ///
    /// While a location is simulated (``simulatedLocation`` isn't nil), a manager that starts
    /// updating gets it instead of starting Core Location, every updating manager gets each new
    /// one, and `requestLocation` and `location` answer with it. When simulation begins, the
    /// real updates of managers already updating stop; when it ends, they start again.
    final class LocationSimulator: @unchecked Sendable {
        // @unchecked: `defaults` is thread-safe and the rest of the mutable state is behind `state`.

        static let shared = LocationSimulator()

        private static let latKey = "com.debugdrawer.location.latitude"
        private static let lonKey = "com.debugdrawer.location.longitude"
        private static let enabledKey = "com.debugdrawer.location.enabled"

        private let defaults: UserDefaults
        private let service: any LocationService

        // A lock rather than an actor: the swizzled CLLocationManager methods ask synchronously,
        // on whatever thread the app calls them from. The standard library's Mutex needs iOS 18;
        // the package supports 17. Unchecked state: it holds weak references to managers, which
        // aren't Sendable, and only ever hands them to their delegates on the main thread.
        private let state = OSAllocatedUnfairLock(uncheckedState: State())

        private struct State {
            /// The managers between `startUpdatingLocation` and `stopUpdatingLocation`.
            var updating: [UpdatingManager] = []
            /// The route's latest point, while one plays.
            var route: CLLocation?
        }

        // @unchecked: the manager is only messaged on the main thread, as Core Location messages
        // the delegate of a manager made there.
        private struct UpdatingManager: @unchecked Sendable {
            weak var manager: CLLocationManager?
        }

        /// - Parameters:
        ///   - defaults: Where the switch and the fixed coordinate are kept: the drawer's own suite,
        ///     apart from the app's defaults.
        ///   - service: Core Location's own behavior, for the calls the simulator lets through.
        init(defaults: UserDefaults = .debugDrawer, service: some LocationService = CoreLocationService()) {
            self.defaults = defaults
            self.service = service
        }

        // MARK: - State

        /// Whether locations are simulated. Kept across launches.
        var isEnabled: Bool {
            get { defaults.bool(forKey: Self.enabledKey) }
            set { change { defaults.set(newValue, forKey: Self.enabledKey) } }
        }

        /// The fixed location given while no route plays, or nil for none. Kept across launches.
        ///
        /// Setting it traps when the coordinate is out of range (`CLLocationCoordinate2DIsValid`);
        /// the plugin's form applies only coordinates in range.
        var coordinate: CLLocationCoordinate2D? {
            get {
                guard let latitude = defaults.object(forKey: Self.latKey) as? Double,
                      let longitude = defaults.object(forKey: Self.lonKey) as? Double
                else { return nil }
                let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                return CLLocationCoordinate2DIsValid(coordinate) ? coordinate : nil
            }
            set {
                if let newValue {
                    precondition(CLLocationCoordinate2DIsValid(newValue), "Latitude must be in -90...90 and longitude in -180...180")
                }
                change {
                    defaults.set(newValue?.latitude, forKey: Self.latKey)
                    defaults.set(newValue?.longitude, forKey: Self.lonKey)
                }
            }
        }

        /// The location apps are given: the route's latest point while one plays, else the fixed
        /// coordinate, while spoofing is on.
        var simulatedLocation: CLLocation? {
            guard isEnabled else { return nil }
            if let route = state.withLockUnchecked({ $0.route }) { return route }
            return coordinate.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
        }

        // MARK: - Route playback

        /// Gives every updating manager a route's next point, and keeps it in effect until the next.
        func deliverRoute(_ location: CLLocation) {
            change { state.withLockUnchecked { $0.route = location } }
        }

        /// Ends a route: the fixed coordinate, if one is set, is in effect again.
        func endRoute() {
            change { state.withLockUnchecked { $0.route = nil } }
        }

        // MARK: - Presets

        struct PresetLocation: Identifiable {
            let id = UUID()
            let name: String
            let latitude: Double
            let longitude: Double
        }

        static let presets: [PresetLocation] = [
            PresetLocation(name: "New York, USA", latitude: 40.7128, longitude: -74.0060),
            PresetLocation(name: "London, UK", latitude: 51.5099, longitude: -0.1337),
            PresetLocation(name: "Tokyo, Japan", latitude: 35.6762, longitude: 139.6503),
            PresetLocation(name: "Sydney, Australia", latitude: -33.8634, longitude: 151.2110),
            PresetLocation(name: "Sao Paulo, Brazil", latitude: -23.5505, longitude: -46.6333)
        ]

        // MARK: - CLLocationManager's calls

        /// The manager's `startUpdatingLocation`: tracks it, then gives it the simulated location
        /// at the next turn of the main run loop, as Core Location answers, or starts its real
        /// updates while none is simulated.
        func startUpdatingLocation(for manager: CLLocationManager) {
            state.withLockUnchecked { state in
                state.updating.removeAll { $0.manager == nil }
                if !state.updating.contains(where: { $0.manager === manager }) {
                    state.updating.append(UpdatingManager(manager: manager))
                }
            }
            guard simulatedLocation != nil else {
                service.startUpdatingLocation(manager)
                return
            }
            let started = UpdatingManager(manager: manager)
            DispatchQueue.main.async {
                // What is simulated then, to a manager still updating then.
                guard let manager = started.manager, self.isUpdating(manager), let location = self.simulatedLocation else { return }
                Self.deliver(location, to: [manager])
            }
        }

        /// The manager's `stopUpdatingLocation`: no more locations, simulated or real.
        func stopUpdatingLocation(for manager: CLLocationManager) {
            state.withLockUnchecked { $0.updating.removeAll { $0.manager == nil || $0.manager === manager } }
            service.stopUpdatingLocation(manager)
        }

        /// The manager's `requestLocation`: the simulated location once, at the next turn of the
        /// main run loop, or a real one while none is simulated.
        func requestLocation(for manager: CLLocationManager) {
            guard simulatedLocation != nil else {
                service.requestLocation(manager)
                return
            }
            let requesting = UpdatingManager(manager: manager)
            DispatchQueue.main.async {
                guard let manager = requesting.manager, let location = self.simulatedLocation else { return }
                Self.deliver(location, to: [manager])
            }
        }

        /// The manager's `location`: the simulated location, or its last real one.
        func location(for manager: CLLocationManager) -> CLLocation? {
            simulatedLocation ?? service.location(of: manager)
        }

        // MARK: - Uninstall

        /// Lets go of every manager: one still updating while a location was simulated gets its
        /// real updates started again, as turning spoofing off does, and the route's point is
        /// forgotten. The switch and the coordinate stay saved for the next install.
        ///
        /// Called before the swizzles are put back, while ``CoreLocationService`` still reaches
        /// Core Location's code through the exchanged selectors.
        func release() {
            let wasSimulating = simulatedLocation != nil
            let managers = updatingManagers()
            state.withLockUnchecked { state in
                state.updating = []
                state.route = nil
            }
            if wasSimulating {
                managers.forEach(service.startUpdatingLocation)
            }
        }

        // MARK: - Delivery

        /// Makes a change to what is simulated, then moves the updating managers to the result:
        /// real updates stop when simulation begins and start again when it ends, and every new
        /// simulated location is delivered.
        private func change(_ body: () -> Void) {
            let before = simulatedLocation
            body()
            let after = simulatedLocation
            let managers = updatingManagers()
            switch (before, after) {
            case (nil, nil):
                return
            case let (nil, location?):
                managers.forEach(service.stopUpdatingLocation)
                Self.deliver(location, to: managers)
            case let (_?, location?):
                Self.deliver(location, to: managers)
            case (_?, nil):
                managers.forEach(service.startUpdatingLocation)
            }
        }

        private func updatingManagers() -> [CLLocationManager] {
            state.withLockUnchecked { state in
                state.updating.removeAll { $0.manager == nil }
                return state.updating.compactMap(\.manager)
            }
        }

        private func isUpdating(_ manager: CLLocationManager) -> Bool {
            state.withLockUnchecked { $0.updating.contains { $0.manager === manager } }
        }

        private static func deliver(_ location: CLLocation, to managers: [CLLocationManager]) {
            for manager in managers {
                manager.delegate?.locationManager?(manager, didUpdateLocations: [location])
            }
        }
    }
#endif
