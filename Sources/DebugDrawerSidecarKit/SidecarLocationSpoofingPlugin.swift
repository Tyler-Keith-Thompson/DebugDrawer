import DebugDrawer
import DebugDrawerLocation
import Foundation
import SwiftUI

// The sidecar's half of location spoofing (DD-122): whether the app's readings are spoofed and to
// where, a latitude and longitude to spoof, a few places to pick, and Stop Spoofing, under a
// warning that says what a spoof does, as the capability is high risk. It ships in the kit, beside
// Environments, as the capability describes itself (a coordinate is all it takes), so every
// sidecar would draw the same form. Spoof sends only a coordinate on the Earth, as the receiver
// would refuse any other. Like Environments it doesn't open the app: a spoof waits in the store and
// lands as the app comes to the foreground. The places repeat the Location plugin's presets
// (`LocationSimulator.presets`): the kit doesn't link the drawer's plugin, and five rows cost less
// than a dependency on it.

#if DEBUG
    extension DebugDrawerSidecarPlugin {
        /// Location spoofing (`DebugDrawerReceiverCapability.locationSpoofing(_:)`): whether the
        /// app's readings are spoofed, a latitude and longitude or a place to spoof them to, and
        /// Stop Spoofing, under a warning that the app reads the location as the device's until the
        /// session ends.
        @MainActor public static var locationSpoofing: DebugDrawerSidecarPlugin {
            DebugDrawerSidecarPlugin(
                id: LocationSpoofing.pluginID, title: "Location", icon: "location.circle",
                snapshot: LocationSpoofing.Snapshot.self, command: LocationSpoofing.Command.self
            ) { transport in
                LocationSpoofingPlugin(transport: transport)
            }
        }
    }

    /// The app's location, spoofed from the sidecar.
    struct LocationSpoofingPlugin: DebugDrawerPlugin {
        let transport: DebugDrawerPluginTransport<LocationSpoofing.Snapshot, LocationSpoofing.Command>
        let title = "Location"
        let icon = "location.circle"

        var body: some View {
            LocationSpoofingTransportView(transport: transport)
        }
    }

    /// The spoofing over the capability's snapshot, sending what the view asks.
    struct LocationSpoofingTransportView: View {
        @ObservedObject var transport: DebugDrawerPluginTransport<LocationSpoofing.Snapshot, LocationSpoofing.Command>

        var body: some View {
            LocationSpoofingView(snapshot: transport.snapshot) { transport.send($0) }
        }
    }

    /// A place the sidecar offers to spoof to.
    struct LocationSpoofingPlace: Identifiable, Equatable {
        let name: String
        let coordinate: LocationCoordinate

        /// Its name: no two places share one.
        var id: String { name }

        static let all = [
            LocationSpoofingPlace(name: "New York, USA", coordinate: LocationCoordinate(latitude: 40.7128, longitude: -74.0060)),
            LocationSpoofingPlace(name: "London, UK", coordinate: LocationCoordinate(latitude: 51.5099, longitude: -0.1337)),
            LocationSpoofingPlace(name: "Tokyo, Japan", coordinate: LocationCoordinate(latitude: 35.6762, longitude: 139.6503)),
            LocationSpoofingPlace(name: "Sydney, Australia", coordinate: LocationCoordinate(latitude: -33.8634, longitude: 151.2110)),
            LocationSpoofingPlace(name: "Sao Paulo, Brazil", coordinate: LocationCoordinate(latitude: -23.5505, longitude: -46.6333))
        ]
    }

    /// The warning, the app's location now with Stop Spoofing while spoofed, the coordinate fields
    /// with Spoof, and the places. A function of the snapshot and the send action; the fields'
    /// text is its own.
    struct LocationSpoofingView: View {
        let snapshot: LocationSpoofing.Snapshot
        let send: (LocationSpoofing.Command) -> Void
        @State private var latitudeText = ""
        @State private var longitudeText = ""

        var body: some View {
            DebugDrawerSection("High Risk") {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    DebugDrawerIssueGlyph(.warning)
                        .accessibilityHidden(true)
                    Text(
                        "Spoofing makes the app take this location for the device's until the session ends. "
                            + "The app is told, and its fraud checks may flag the account."
                    )
                    .debugDrawerFont(.label)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .debugDrawerRowPadding()
                .accessibilityElement(children: .combine)
                .accessibilityLabel("High risk: the app takes the spoofed location for the device's until the session ends, and is told")
                .accessibilityIdentifier("LocationSpoofingRiskWarning")
            }
            DebugDrawerSection("Location") {
                if let coordinate = snapshot.coordinate {
                    DebugDrawerKeyValueRow("Spoofed", value: coordinate.summary)
                        .accessibilityIdentifier("LocationSpoofingStatus")
                    DebugDrawerActionRow {
                        Button("Stop Spoofing") { send(.stop) }
                            .debugDrawerButtonStyle(.secondary)
                            .accessibilityLabel("Stop Spoofing")
                            .accessibilityHint("The app reads the device's real location again")
                    }
                } else {
                    DebugDrawerKeyValueRow("Spoofed", value: "No: the app reads the real location")
                        .accessibilityIdentifier("LocationSpoofingStatus")
                }
            }
            DebugDrawerSection("Spoof") {
                DebugDrawerRow("Coordinate", systemImage: nil) {
                    Text("Latitude -90 to 90, longitude -180 to 180")
                } accessory: {
                    HStack(spacing: 6) {
                        TextField("Latitude", text: $latitudeText)
                            .debugDrawerTextFieldStyle()
                        #if os(iOS)
                            .keyboardType(.numbersAndPunctuation)
                        #endif
                            .accessibilityLabel("Latitude")
                        TextField("Longitude", text: $longitudeText)
                            .debugDrawerTextFieldStyle()
                        #if os(iOS)
                            .keyboardType(.numbersAndPunctuation)
                        #endif
                            .accessibilityLabel("Longitude")
                        Button("Spoof") {
                            if let typed {
                                send(.spoof(typed))
                            }
                        }
                        .debugDrawerButtonStyle(.primary)
                        .disabled(typed == nil || typed == snapshot.coordinate)
                        .accessibilityLabel("Spoof the typed coordinate")
                    }
                }
                .accessibilityIdentifier("LocationSpoofingCoordinate")
                ForEach(LocationSpoofingPlace.all) { place in
                    DebugDrawerRow(place.name, systemImage: place.coordinate == snapshot.coordinate ? "checkmark.circle.fill" : "mappin") {
                        Text(place.coordinate.summary)
                    } accessory: {
                        if place.coordinate == snapshot.coordinate {
                            Text("Spoofed")
                                .debugDrawerForegroundStyle(.accent)
                        } else {
                            Button("Spoof") { send(.spoof(place.coordinate)) }
                                .debugDrawerButtonStyle(.primary)
                                .accessibilityLabel("Spoof \(place.name)")
                        }
                    }
                    .accessibilityIdentifier("LocationSpoofingPlace-\(place.name)")
                }
            }
        }

        /// The coordinate the fields hold, or `nil` when it isn't one on the Earth.
        private var typed: LocationCoordinate? {
            LocationCoordinate(latitudeText: latitudeText, longitudeText: longitudeText)
        }
    }

    extension LocationCoordinate {
        /// The coordinate two fields hold, or `nil` when either isn't a number or it isn't on the
        /// Earth: the receiver would refuse it.
        init?(latitudeText: String, longitudeText: String) {
            guard let latitude = Double(latitudeText.trimmingCharacters(in: .whitespaces)),
                  let longitude = Double(longitudeText.trimmingCharacters(in: .whitespaces))
            else { return nil }
            self.init(latitude: latitude, longitude: longitude)
            guard isValid else { return nil }
        }

        /// The coordinate as a row says it: degrees to four places, with a point whatever the
        /// locale, as the fields take them.
        fileprivate var summary: String {
            String(format: "%.4f, %.4f", latitude, longitude)
        }
    }
#else
    // The release stand-in: the same member, over a plugin that draws nothing; a release build's
    // transports connect to nothing anyway.

    extension DebugDrawerSidecarPlugin {
        /// Location spoofing; release builds show nothing.
        @MainActor public static var locationSpoofing: DebugDrawerSidecarPlugin {
            DebugDrawerSidecarPlugin(
                id: LocationSpoofing.pluginID, title: "Location", icon: "location.circle",
                snapshot: LocationSpoofing.Snapshot.self, command: LocationSpoofing.Command.self
            ) { _ in
                LocationSpoofingPlugin()
            }
        }
    }

    /// Draws nothing.
    struct LocationSpoofingPlugin: DebugDrawerPlugin {
        let title = "Location"
        let icon = "location.circle"

        var body: some View {
            EmptyView()
        }
    }
#endif
