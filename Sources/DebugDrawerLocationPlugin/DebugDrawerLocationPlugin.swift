#if DEBUG
    import CoreLocation
    import DebugDrawer
    import ObjectiveC
    import SwiftUI

    // MARK: - Location toolkit

    /// Manages simulated location state and CLLocationManager swizzling.
    final class LocationSimulator: @unchecked Sendable {
        static let shared = LocationSimulator()

        private static let latKey = "com.debugdrawer.location.latitude"
        private static let lonKey = "com.debugdrawer.location.longitude"
        private static let enabledKey = "com.debugdrawer.location.enabled"

        private var swizzled = false

        /// All tracked CLLocationManager instances for re-delivery.
        private var managers: [WeakManager] = []

        private struct WeakManager {
            weak var manager: CLLocationManager?
        }

        private init() {}

        // MARK: - State

        var isEnabled: Bool {
            get { UserDefaults.standard.bool(forKey: Self.enabledKey) }
            set {
                UserDefaults.standard.set(newValue, forKey: Self.enabledKey)
                if newValue {
                    installSwizzlesIfNeeded()
                    deliverToAll()
                }
            }
        }

        var latitude: Double {
            get { UserDefaults.standard.double(forKey: Self.latKey) }
            set {
                UserDefaults.standard.set(newValue, forKey: Self.latKey)
                if isEnabled { deliverToAll() }
            }
        }

        var longitude: Double {
            get { UserDefaults.standard.double(forKey: Self.lonKey) }
            set {
                UserDefaults.standard.set(newValue, forKey: Self.lonKey)
                if isEnabled { deliverToAll() }
            }
        }

        var simulatedLocation: CLLocation? {
            guard isEnabled, latitude != 0 || longitude != 0 else { return nil }
            return CLLocation(latitude: latitude, longitude: longitude)
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
            managers.removeAll { $0.manager == nil }
            for weak in managers {
                weak.manager?.delegate?.locationManager?(weak.manager!, didUpdateLocations: [location])
            }
        }

        // MARK: - Swizzling

        func installSwizzlesIfNeeded() {
            guard !swizzled else { return }
            swizzled = true

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
        }
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

    // MARK: - Plugin

    public struct LocationPlugin: DebugDrawerPlugin {
        public var title = "Location Simulator"
        public var category = "App"
        public var icon = "location.circle"

        public init() {}

        public var body: some View {
            LocationPluginView()
        }
    }

    /// Reads and writes `LocationSimulator.shared`; `LocationForm` draws it.
    private struct LocationPluginView: View {
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
        // Grows with the text, so "Lat" and "Lon" keep fitting their column at large sizes.
        @ScaledMetric(relativeTo: .caption) private var labelWidth = 24

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Spoof Location", isOn: $isEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)

                if isEnabled {
                    coordinateField("Lat", "Latitude", text: $latitudeText)
                    coordinateField("Lon", "Longitude", text: $longitudeText)

                    if let active {
                        Text("Active: \(String(format: "%.4f", active.latitude)), \(String(format: "%.4f", active.longitude))")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.green)
                    }

                    Divider()

                    Text("Presets")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(presets) { preset in
                        Button {
                            onPreset(preset)
                        } label: {
                            HStack {
                                Text(preset.name)
                                    .font(.caption2)
                                Spacer()
                                Text("\(String(format: "%.2f", preset.latitude)), \(String(format: "%.2f", preset.longitude))")
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }

        private func coordinateField(_ shortName: String, _ name: String, text: Binding<String>) -> some View {
            HStack(spacing: 4) {
                Text(shortName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: labelWidth, alignment: .leading)
                TextField(name, text: text)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption2, design: .monospaced))
                    .accessibilityLabel(name)
                    #if os(iOS)
                        .keyboardType(.decimalPad)
                    #endif
            }
        }
    }

    // MARK: - Convenience installer

    public extension DebugDrawer {
        func installLocation() {
            registerGlobal(LocationPlugin())
        }
    }
#endif
