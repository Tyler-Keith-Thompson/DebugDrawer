import CoreLocation
import DebugDrawer
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Plugin

// The public API compiles in every configuration; the implementation under `#if DEBUG` below does
// not, so release builds get an empty view and an installer that swizzles and registers nothing.

/// Spoofs the location the app's `CLLocationManager`s report: a fixed coordinate, a preset, or a
/// GPX route played back in time.
///
/// While spoofing is on and a coordinate is set or a route plays, a manager that calls
/// `startUpdatingLocation` gets the simulated location instead of real updates, then each new
/// coordinate or route point as it changes; `requestLocation` and `location` answer with it too.
/// A manager already updating when spoofing begins stops getting real updates, and turning
/// spoofing off starts them again. The switch and the coordinate are kept across launches.
///
/// Only `CLLocationManager`'s location updates are covered. These still report the real
/// location, which on the iOS simulator is the one Xcode or `simctl location` sets:
///
/// - `CLLocationUpdate.liveUpdates()` and `CLMonitor`: no public API reaches what they yield.
/// - MapKit's user location (`showsUserLocation`, `UserAnnotation`, `MapUserLocationButton`).
/// - Region monitoring, significant-change and visit updates, and heading.
///
/// Authorization isn't simulated: `authorizationStatus` is the real one, and a spoofed location
/// is delivered whether or not the app is authorized.
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
    /// Registers ``LocationPlugin`` and swaps `CLLocationManager`'s location methods for the
    /// simulator's, so spoofing kept from the last launch is in effect at once.
    ///
    /// Call it at startup, before the app starts location updates: a manager that started
    /// before it isn't tracked. Release builds do nothing.
    func installLocation() {
        #if DEBUG
            _ = LocationSwizzles.installed
            registerGlobal(LocationPlugin())
        #endif
    }
}

#if DEBUG
    /// Reads and writes `LocationSimulator.shared` and `RoutePlayer.shared`; `LocationForm` and
    /// `RouteSection` draw them. It presents the file importer for Import GPX….
    private struct LocationPluginView: View {
        @ObservedObject private var player = RoutePlayer.shared
        @State private var isImporting = false
        @State private var isEnabled: Bool = LocationSimulator.shared.isEnabled
        @State private var latText: String = LocationSimulator.shared.coordinate.map { String($0.latitude) } ?? ""
        @State private var lonText: String = LocationSimulator.shared.coordinate.map { String($0.longitude) } ?? ""

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
                LocationSimulator.shared.coordinate = CLLocationCoordinate2D(latitude: preset.latitude, longitude: preset.longitude)
            }
            .onChange(of: isEnabled) { _, newValue in
                // The Route section goes with the switch, so a route stops with it.
                if !newValue { player.stop() }
                LocationSimulator.shared.isEnabled = newValue
            }
            .onChange(of: latText) { _, newValue in applyCoordinate(latitude: newValue, longitude: lonText) }
            .onChange(of: lonText) { _, newValue in applyCoordinate(latitude: latText, longitude: newValue) }
        }

        /// Spoofs the typed coordinate once both fields hold numbers in range. Until then the one
        /// in effect stays, and the Active row shows it.
        private func applyCoordinate(latitude: String, longitude: String) {
            guard let latitude = Double(latitude), let longitude = Double(longitude) else { return }
            let typed = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            guard CLLocationCoordinate2DIsValid(typed) else { return }
            LocationSimulator.shared.coordinate = typed
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
                        // Not .decimalPad, which has no minus sign for southern and western coordinates.
                        .keyboardType(.numbersAndPunctuation)
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
