import Combine
import DebugDrawer
import Foundation

#if DEBUG
    import CoreLocation

    // The model holds values only: what managers are given goes to a `LocationOverride` (the
    // simulator the swizzled CLLocationManager methods ask, which keeps the switch and coordinate
    // in a `LocationSpoofingStore`), the method swap to a `LocationInterception`, and imported
    // files come from `GPXFileReading`. Every command lands before `perform(_:)` returns, so
    // commands take effect in the order sent and a field bound through a direct transport reads
    // back what was typed; a route's later points arrive on the player's clock.

    /// The Location Simulator's state and behavior, without its views: the spoofing switch, the
    /// coordinate fields, the location in effect, the presets and the route playback, read as a
    /// ``LocationSnapshot`` and changed with a ``LocationCommand``.
    ///
    /// The plugin's view reaches it through a `DebugDrawerPluginTransport`:
    ///
    /// ```swift
    /// let transport = DebugDrawerPluginTransport.direct(to: LocationModel.shared)
    /// ```
    ///
    /// Release builds get a stand-in whose snapshot holds nothing and which ignores every command.
    @MainActor
    public final class LocationModel: DebugDrawerPluginModel {
        /// The model over the simulator the app's location managers ask, which the plugin shows.
        public static let shared = LocationModel()

        @Published private var latitudeText: String
        @Published private var longitudeText: String

        private let simulator: any LocationOverride
        private let interception: any LocationInterception
        private let files: any GPXFileReading
        private let player: RoutePlayer
        private var playerChanges: AnyCancellable?
        /// The drawers the plugin is installed in; the methods stay swapped while any holds it.
        private var installations: Set<ObjectIdentifier> = []

        /// - Parameters:
        ///   - simulator: What the app's location managers are given.
        ///   - interception: Swaps `CLLocationManager`'s location methods for the simulator's.
        ///   - files: Reads the GPX files imported.
        ///   - scheduler: The clock route playback runs on.
        ///   - routes: The routes to choose from, the first chosen; at least one.
        init(
            simulator: any LocationOverride = LocationSimulator.shared,
            interception: any LocationInterception = _LocationInterception(),
            files: any GPXFileReading = _GPXFileReading(),
            scheduler: any PlaybackScheduler = TimerPlaybackScheduler(),
            routes: [Route] = Route.samples
        ) {
            self.simulator = simulator
            self.interception = interception
            self.files = files
            let coordinate = simulator.coordinate
            latitudeText = coordinate.map { String($0.latitude) } ?? ""
            longitudeText = coordinate.map { String($0.longitude) } ?? ""
            player = RoutePlayer(routes: routes, scheduler: scheduler, simulator: simulator)
            // Playback moves on the player's clock; each point delivered is a new snapshot.
            playerChanges = player.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        }

        public var snapshot: LocationSnapshot {
            LocationSnapshot(
                isEnabled: simulator.isEnabled,
                latitudeText: latitudeText,
                longitudeText: longitudeText,
                coordinate: simulator.coordinate.map(LocationCoordinate.init),
                active: simulator.simulatedLocation.map { LocationCoordinate($0.coordinate) },
                presets: LocationSimulator.presets,
                routes: player.routes,
                routeID: player.route.id,
                speed: player.speed,
                playback: player.playback,
                importFailure: player.importFailure
            )
        }

        public func perform(_ command: LocationCommand) {
            switch command.action {
            case let .setEnabled(isEnabled):
                objectWillChange.send()
                // The Route section goes with the switch, so a route stops with it.
                if !isEnabled { player.stop() }
                simulator.isEnabled = isEnabled
            case let .setLatitudeText(text):
                latitudeText = text
                applyTypedCoordinate()
            case let .setLongitudeText(text):
                longitudeText = text
                applyTypedCoordinate()
            case let .setCoordinate(coordinate):
                setCoordinate(coordinate)
            case let .choosePreset(preset):
                setCoordinate(LocationCoordinate(latitude: preset.latitude, longitude: preset.longitude))
            case .selectRoute, .setSpeed, .play, .pause, .stop, .importRoute:
                performRoute(command.action)
            }
        }

        /// Hands a route's command to the player.
        private func performRoute(_ action: LocationCommand.Action) {
            switch action {
            case let .selectRoute(id):
                player.select(id)
            case let .setSpeed(speed):
                player.speed = speed
            case .play:
                player.play()
            case .pause:
                player.pause()
            case .stop:
                player.stop()
            case let .importRoute(url):
                let files = files
                player.importFile(Result { () throws(GPXError) in try files.track(at: url) }, from: url)
            case .setEnabled, .setLatitudeText, .setLongitudeText, .setCoordinate, .choosePreset:
                // `perform(_:)` handles these itself.
                break
            }
        }

        /// Counts `drawer` as one the plugin is installed in, and swaps `CLLocationManager`'s
        /// location methods for the simulator's, so spoofing kept from the last launch is in effect
        /// at once.
        func install(in drawer: ObjectIdentifier) {
            installations.insert(drawer)
            interception.install()
        }

        /// Uncounts `drawer`; once no drawer holds the plugin, stops a route playing, hands every
        /// manager the simulator tracked back to Core Location and gives each swapped method its
        /// original implementation back. The switch, the coordinate and the fields stay.
        func uninstall(from drawer: ObjectIdentifier) {
            guard installations.remove(drawer) != nil, installations.isEmpty else { return }
            objectWillChange.send()
            player.stop()
            simulator.release()
            interception.uninstall()
        }

        /// Spoofs the typed coordinate once both fields hold numbers in range. Until then the one
        /// in effect stays.
        private func applyTypedCoordinate() {
            guard let latitude = Double(latitudeText), let longitude = Double(longitudeText) else { return }
            let typed = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            guard CLLocationCoordinate2DIsValid(typed) else { return }
            simulator.coordinate = typed
        }

        /// Spoofs `coordinate` and shows it in the fields, or with nil clears both; ignores one out
        /// of range, which the simulator would trap on.
        private func setCoordinate(_ coordinate: LocationCoordinate?) {
            let location = coordinate.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
            if let location, !CLLocationCoordinate2DIsValid(location) { return }
            objectWillChange.send()
            latitudeText = coordinate.map { String($0.latitude) } ?? ""
            longitudeText = coordinate.map { String($0.longitude) } ?? ""
            simulator.coordinate = location
        }
    }

    extension LocationCoordinate {
        fileprivate init(_ coordinate: CLLocationCoordinate2D) {
            self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
        }
    }
#else
    // The release stand-in: the same members, and nothing behind them.

    /// Release builds simulate no location: this stand-in's snapshot holds nothing, and it ignores
    /// every command.
    @MainActor
    public final class LocationModel: DebugDrawerPluginModel {
        /// The stand-in model.
        public static let shared = LocationModel()

        private init() {}

        /// Always empty.
        public var snapshot: LocationSnapshot {
            LocationSnapshot()
        }

        /// Does nothing.
        ///
        /// - Parameter command: Ignored.
        public func perform(_ command: LocationCommand) {}
    }
#endif
