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
            PresetLocation(name: "Sao Paulo, Brazil", latitude: -23.5505, longitude: -46.6333),
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
               let swizzledM = class_getInstanceMethod(CLLocationManager.self, #selector(CLLocationManager._dd_swizzledInit))
            {
                method_exchangeImplementations(original, swizzledM)
            }

            // Swizzle startUpdatingLocation
            if let original = class_getInstanceMethod(CLLocationManager.self, #selector(CLLocationManager.startUpdatingLocation)),
               let swizzledM = class_getInstanceMethod(CLLocationManager.self, #selector(CLLocationManager._dd_swizzledStartUpdating))
            {
                method_exchangeImplementations(original, swizzledM)
            }

            // Swizzle requestLocation
            if let original = class_getInstanceMethod(CLLocationManager.self, #selector(CLLocationManager.requestLocation)),
               let swizzledM = class_getInstanceMethod(CLLocationManager.self, #selector(CLLocationManager._dd_swizzledRequestLocation))
            {
                method_exchangeImplementations(original, swizzledM)
            }

            // Swizzle location getter
            if let original = class_getInstanceMethod(CLLocationManager.self, #selector(getter: CLLocationManager.location)),
               let swizzledM = class_getInstanceMethod(CLLocationManager.self, #selector(CLLocationManager._dd_swizzledLocation))
            {
                method_exchangeImplementations(original, swizzledM)
            }
        }
    }

    // MARK: - CLLocationManager swizzled methods

    extension CLLocationManager {
        @objc dynamic func _dd_swizzledInit() -> CLLocationManager {
            let manager = _dd_swizzledInit() // calls original (swapped)
            LocationSimulator.shared.track(manager)
            return manager
        }

        @objc dynamic func _dd_swizzledStartUpdating() {
            if let simulated = LocationSimulator.shared.simulatedLocation {
                delegate?.locationManager?(self, didUpdateLocations: [simulated])
            } else {
                _dd_swizzledStartUpdating() // calls original
            }
        }

        @objc dynamic func _dd_swizzledRequestLocation() {
            if let simulated = LocationSimulator.shared.simulatedLocation {
                delegate?.locationManager?(self, didUpdateLocations: [simulated])
            } else {
                _dd_swizzledRequestLocation() // calls original
            }
        }

        @objc dynamic func _dd_swizzledLocation() -> CLLocation? {
            if let simulated = LocationSimulator.shared.simulatedLocation {
                return simulated
            }
            return _dd_swizzledLocation() // calls original
        }
    }

    // MARK: - Plugin

    public struct LocationPlugin: DebugDrawerPlugin {
        public var title = "Location Simulator"
        public var icon = "location.circle"

        public init() {}

        public var body: some View {
            LocationPluginView()
        }
    }

    private struct LocationPluginView: View {
        @State private var isEnabled: Bool = LocationSimulator.shared.isEnabled
        @State private var latText: String = {
            let v = LocationSimulator.shared.latitude
            return v == 0 ? "" : String(v)
        }()
        @State private var lonText: String = {
            let v = LocationSimulator.shared.longitude
            return v == 0 ? "" : String(v)
        }()

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Spoof Location", isOn: $isEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .onChange(of: isEnabled) { _, newValue in
                        LocationSimulator.shared.isEnabled = newValue
                    }

                if isEnabled {
                    HStack(spacing: 4) {
                        Text("Lat")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .leading)
                        TextField("Latitude", text: $latText)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 10, design: .monospaced))
                            #if os(iOS)
                                .keyboardType(.decimalPad)
                            #endif
                            .onChange(of: latText) { _, newValue in
                                if let v = Double(newValue) {
                                    LocationSimulator.shared.latitude = v
                                }
                            }
                    }

                    HStack(spacing: 4) {
                        Text("Lon")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .leading)
                        TextField("Longitude", text: $lonText)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 10, design: .monospaced))
                            #if os(iOS)
                                .keyboardType(.decimalPad)
                            #endif
                            .onChange(of: lonText) { _, newValue in
                                if let v = Double(newValue) {
                                    LocationSimulator.shared.longitude = v
                                }
                            }
                    }

                    if LocationSimulator.shared.simulatedLocation != nil {
                        Text("Active: \(String(format: "%.4f", LocationSimulator.shared.latitude)), \(String(format: "%.4f", LocationSimulator.shared.longitude))")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.green)
                    }

                    Divider()

                    Text("Presets")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(LocationSimulator.presets) { preset in
                        Button {
                            latText = String(preset.latitude)
                            lonText = String(preset.longitude)
                            LocationSimulator.shared.latitude = preset.latitude
                            LocationSimulator.shared.longitude = preset.longitude
                        } label: {
                            HStack {
                                Text(preset.name)
                                    .font(.system(size: 10))
                                Spacer()
                                Text("\(String(format: "%.2f", preset.latitude)), \(String(format: "%.2f", preset.longitude))")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
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
