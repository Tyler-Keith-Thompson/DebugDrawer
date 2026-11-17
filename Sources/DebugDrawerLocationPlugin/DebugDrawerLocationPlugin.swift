import CoreLocation
import DebugDrawer
import ObjectiveC
import os
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Plugin

// The public API compiles in every configuration; the implementation under `#if DEBUG` below does
// not, so release builds get an empty view and an installer that swizzles and registers nothing.

public struct LocationPlugin: DebugDrawerPlugin {
    public var title = "Location Simulator"
    public var category = "App"
    public var icon = "location.circle"

    public init() {}

    public var body: some View {
        #if DEBUG
            LocationPluginView()
        #else
            EmptyView()
        #endif
    }
}

// MARK: - Convenience installer

public extension DebugDrawer {
    func installLocation() {
        #if DEBUG
            // At install, so a manager the app creates before spoofing is turned on is tracked too,
            // and a route's points reach it. Until then each swapped method calls the original.
            LocationSimulator.shared.installSwizzlesIfNeeded()
            registerGlobal(LocationPlugin())
        #endif
    }
}

#if DEBUG
    // MARK: - Location toolkit

    /// Manages simulated location state and CLLocationManager swizzling.
    final class LocationSimulator: @unchecked Sendable {
        static let shared = LocationSimulator()

        private static let latKey = "com.debugdrawer.location.latitude"
        private static let lonKey = "com.debugdrawer.location.longitude"
        private static let enabledKey = "com.debugdrawer.location.enabled"

        private let defaults: UserDefaults

        /// All tracked CLLocationManager instances for re-delivery.
        private var managers: [WeakManager] = []

        // A lock rather than an actor: the swizzled `location` getter reads it synchronously, on
        // whatever thread the app asks from. The standard library's Mutex needs iOS 18; the package supports 17.
        private let routeLocation = OSAllocatedUnfairLock<CLLocation?>(initialState: nil)

        private struct WeakManager {
            weak var manager: CLLocationManager?
        }

        /// - Parameter defaults: Where the switch and the fixed coordinate are kept.
        init(defaults: UserDefaults = .standard) {
            self.defaults = defaults
        }

        // MARK: - State

        var isEnabled: Bool {
            get { defaults.bool(forKey: Self.enabledKey) }
            set {
                defaults.set(newValue, forKey: Self.enabledKey)
                if newValue {
                    installSwizzlesIfNeeded()
                    deliverToAll()
                }
            }
        }

        var latitude: Double {
            get { defaults.double(forKey: Self.latKey) }
            set {
                defaults.set(newValue, forKey: Self.latKey)
                if isEnabled { deliverToAll() }
            }
        }

        var longitude: Double {
            get { defaults.double(forKey: Self.lonKey) }
            set {
                defaults.set(newValue, forKey: Self.lonKey)
                if isEnabled { deliverToAll() }
            }
        }

        /// The location apps are given: the route's latest point while one plays, else the fixed
        /// coordinate, while spoofing is on.
        var simulatedLocation: CLLocation? {
            guard isEnabled else { return nil }
            if let route = routeLocation.withLock({ $0 }) { return route }
            guard latitude != 0 || longitude != 0 else { return nil }
            return CLLocation(latitude: latitude, longitude: longitude)
        }

        // MARK: - Route playback

        /// Gives every tracked manager a route's next point, and keeps it in effect until the next.
        func deliverRoute(_ location: CLLocation) {
            routeLocation.withLock { $0 = location }
            deliver(location)
        }

        /// Ends a route: the fixed coordinate, if one is set, is in effect again.
        func endRoute() {
            routeLocation.withLock { $0 = nil }
            deliverToAll()
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

        // MARK: - Manager tracking

        func track(_ manager: CLLocationManager) {
            managers.removeAll { $0.manager == nil }
            guard !managers.contains(where: { $0.manager === manager }) else { return }
            managers.append(WeakManager(manager: manager))
        }

        private func deliverToAll() {
            guard let location = simulatedLocation else { return }
            deliver(location)
        }

        private func deliver(_ location: CLLocation) {
            managers.removeAll { $0.manager == nil }
            for manager in managers.compactMap(\.manager) {
                manager.delegate?.locationManager?(manager, didUpdateLocations: [location])
            }
        }

        // MARK: - Swizzling

        /// Swaps CLLocationManager's methods for the simulator's, once per process: a second swap
        /// would put the originals back.
        func installSwizzlesIfNeeded() {
            _ = Self.swizzles
        }

        private static let swizzles: Void = {

            // Swizzle init to track instances
            if let original = class_getInstanceMethod(CLLocationManager.self, #selector(CLLocationManager.init)),
               let swizzledM = class_getInstanceMethod(CLLocationManager.self, #selector(CLLocationManager.debugDrawerSwizzledInit)) {
                method_exchangeImplementations(original, swizzledM)
            }

            // Swizzle startUpdatingLocation
            if let original = class_getInstanceMethod(CLLocationManager.self, #selector(CLLocationManager.startUpdatingLocation)),
               let swizzledM = class_getInstanceMethod(CLLocationManager.self, #selector(CLLocationManager.debugDrawerSwizzledStartUpdating)) {
                method_exchangeImplementations(original, swizzledM)
            }

            // Swizzle requestLocation
            if let original = class_getInstanceMethod(CLLocationManager.self, #selector(CLLocationManager.requestLocation)),
               let swizzledM = class_getInstanceMethod(CLLocationManager.self, #selector(CLLocationManager.debugDrawerSwizzledRequestLocation)) {
                method_exchangeImplementations(original, swizzledM)
            }

            // Swizzle location getter
            if let original = class_getInstanceMethod(CLLocationManager.self, #selector(getter: CLLocationManager.location)),
               let swizzledM = class_getInstanceMethod(CLLocationManager.self, #selector(CLLocationManager.debugDrawerSwizzledLocation)) {
                method_exchangeImplementations(original, swizzledM)
            }
        }()
    }

    // MARK: - CLLocationManager swizzled methods

    extension CLLocationManager {
        @objc dynamic func debugDrawerSwizzledInit() -> CLLocationManager {
            let manager = debugDrawerSwizzledInit() // calls original (swapped)
            LocationSimulator.shared.track(manager)
            return manager
        }

        @objc dynamic func debugDrawerSwizzledStartUpdating() {
            if let simulated = LocationSimulator.shared.simulatedLocation {
                delegate?.locationManager?(self, didUpdateLocations: [simulated])
            } else {
                debugDrawerSwizzledStartUpdating() // calls original
            }
        }

        @objc dynamic func debugDrawerSwizzledRequestLocation() {
            if let simulated = LocationSimulator.shared.simulatedLocation {
                delegate?.locationManager?(self, didUpdateLocations: [simulated])
            } else {
                debugDrawerSwizzledRequestLocation() // calls original
            }
        }

        @objc dynamic func debugDrawerSwizzledLocation() -> CLLocation? {
            if let simulated = LocationSimulator.shared.simulatedLocation {
                return simulated
            }
            return debugDrawerSwizzledLocation() // calls original
        }
    }

    /// Reads and writes `LocationSimulator.shared` and `RoutePlayer.shared`; `LocationForm` and
    /// `RouteSection` draw them. It presents the file importer for Import GPX….
    private struct LocationPluginView: View {
        @ObservedObject private var player = RoutePlayer.shared
        @State private var isImporting = false
        @State private var isEnabled: Bool = LocationSimulator.shared.isEnabled
        @State private var latText: String = {
            let latitude = LocationSimulator.shared.latitude
            return latitude == 0 ? "" : String(latitude)
        }()
        @State private var lonText: String = {
            let longitude = LocationSimulator.shared.longitude
            return longitude == 0 ? "" : String(longitude)
        }()

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                form
                if isEnabled {
                    RouteSection(
                        routes: player.routes,
                        selection: Binding(get: { player.route.id }, set: { player.select($0) }),
                        speed: $player.speed,
                        playback: player.playback,
                        importFailure: player.importFailure,
                        actions: RouteActions(
                            play: player.play,
                            pause: player.pause,
                            stop: player.stop,
                            importFile: { isImporting = true }
                        )
                    )
                }
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.gpx, .xml]) { result in
                if case let .success(url) = result {
                    player.importFile(Result { () throws(GPXError) in try GPXTrack(contentsOf: url) }, from: url)
                }
            }
        }

        private var form: some View {
            LocationForm(
                isEnabled: $isEnabled,
                latitudeText: $latText,
                longitudeText: $lonText,
                active: LocationSimulator.shared.simulatedLocation.map {
                    LocationForm.Coordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
                },
                presets: LocationSimulator.presets
            ) { preset in
                latText = String(preset.latitude)
                lonText = String(preset.longitude)
                LocationSimulator.shared.latitude = preset.latitude
                LocationSimulator.shared.longitude = preset.longitude
            }
            .onChange(of: isEnabled) { _, newValue in
                // The Route section goes with the switch, so a route stops with it.
                if !newValue { player.stop() }
                LocationSimulator.shared.isEnabled = newValue
            }
            .onChange(of: latText) { _, newValue in
                if let latitude = Double(newValue) {
                    LocationSimulator.shared.latitude = latitude
                }
            }
            .onChange(of: lonText) { _, newValue in
                if let longitude = Double(newValue) {
                    LocationSimulator.shared.longitude = longitude
                }
            }
        }
    }

    /// The spoofing switch and, while it is on, the coordinate fields, the location in effect and
    /// the presets.
    struct LocationForm: View {
        /// A latitude and longitude in degrees.
        struct Coordinate: Equatable {
            var latitude: Double
            var longitude: Double
        }

        @Binding var isEnabled: Bool
        @Binding var latitudeText: String
        @Binding var longitudeText: String
        /// The location apps are given now, or nil while none is.
        let active: Coordinate?
        let presets: [LocationSimulator.PresetLocation]
        let onPreset: (LocationSimulator.PresetLocation) -> Void
        // Grows with the text, so "Longitude" keeps fitting its column at large sizes.
        @ScaledMetric(relativeTo: .body) private var labelWidth = 72
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                DebugDrawerRow("Spoof Location", isOn: $isEnabled)

                if isEnabled {
                    DebugDrawerSection {
                        coordinateField("Latitude", text: $latitudeText)
                        coordinateField("Longitude", text: $longitudeText)
                        if let active {
                            DebugDrawerIssueRow(
                                "Active",
                                status: "\(String(format: "%.4f", active.latitude)), \(String(format: "%.4f", active.longitude))",
                                severity: .ok
                            )
                        }
                    }

                    DebugDrawerSection("Presets") {
                        ForEach(presets) { preset in
                            Button {
                                onPreset(preset)
                            } label: {
                                // At accessibility text sizes the coordinates go under the name, where
                                // they fit on one line.
                                let layout = dynamicTypeSize.isAccessibilitySize
                                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
                                    : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
                                layout {
                                    Text(preset.name)
                                        .debugDrawerFont(.body)
                                    if !dynamicTypeSize.isAccessibilitySize {
                                        Spacer()
                                    }
                                    Text("\(String(format: "%.2f", preset.latitude)), \(String(format: "%.2f", preset.longitude))")
                                        .debugDrawerFont(.value)
                                        .debugDrawerForegroundStyle(.tertiary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 3)
                            }
                            .debugDrawerButtonStyle(.plain)
                            .accessibilityHint("Spoofs this location")
                        }
                    }
                }
            }
        }

        private func coordinateField(_ name: String, text: Binding<String>) -> some View {
            HStack(spacing: 8) {
                Text(name)
                    .debugDrawerFont(.label)
                    .debugDrawerForegroundStyle(.secondary)
                    .frame(width: labelWidth, alignment: .trailing)
                TextField(name, text: text)
                    .debugDrawerFont(.code)
                    .debugDrawerTextFieldStyle()
                    .accessibilityLabel(name)
                    #if os(iOS)
                        .keyboardType(.decimalPad)
                    #endif
            }
            .padding(.vertical, 3)
        }
    }

    extension UTType {
        /// GPX files, by their extension: the system declares no type for them.
        fileprivate static let gpx = UTType(filenameExtension: "gpx", conformingTo: .xml) ?? .xml
    }

#endif
