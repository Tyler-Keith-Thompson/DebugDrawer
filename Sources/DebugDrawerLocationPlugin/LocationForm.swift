#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The spoofing switch and, while it is on, the coordinate fields, the location in effect and
    /// the presets.
    struct LocationForm: View {
        @Binding var isEnabled: Bool
        @Binding var latitudeText: String
        @Binding var longitudeText: String
        /// The location apps are given now, or nil while none is.
        let active: LocationCoordinate?
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
            // At accessibility text sizes the name goes above the field, as the presets' coordinates
            // go under their names, so the field gets the full width and shows a whole coordinate.
            let isAccessibilitySize = dynamicTypeSize.isAccessibilitySize
            let layout = isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                : AnyLayout(HStackLayout(spacing: 8))
            return layout {
                Text(name)
                    .debugDrawerFont(.label)
                    .debugDrawerForegroundStyle(.secondary)
                    .frame(width: isAccessibilitySize ? nil : labelWidth, alignment: isAccessibilitySize ? .leading : .trailing)
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
#endif
