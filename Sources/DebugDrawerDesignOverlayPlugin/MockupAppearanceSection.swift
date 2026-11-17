#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// Show, the opacity, the blend and the scale.
    struct MockupAppearanceSection: View {
        @Binding var settings: DesignOverlaySettings

        var body: some View {
            DebugDrawerSection("Appearance") {
                DebugDrawerRow("Show Mockup", isOn: $settings.isVisible)
                DebugDrawerRow("Opacity") {
                    HStack(spacing: 8) {
                        Slider(value: $settings.opacity, in: DesignOverlaySettings.opacityRange, step: 0.05)
                            // Not scaled with the text: at accessibility sizes the row stacks the
                            // slider under its title, where a wider minimum would push the
                            // percentage past the panel's edge.
                            .frame(minWidth: 120)
                            .accessibilityLabel("Opacity")
                            .accessibilityValue(settings.opacityText)
                        Text(settings.opacityText)
                            .debugDrawerFont(.value)
                            .debugDrawerForegroundStyle(.secondary)
                            .fixedSize()
                            .accessibilityHidden(true)
                    }
                }
                DebugDrawerRow("Blend") {
                    Picker("Blend", selection: $settings.blend) {
                        ForEach(MockupBlend.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .accessibilityLabel("Blend")
                    .accessibilityElement(children: .contain)
                }
                DebugDrawerRow("Scale") {
                    Picker("Scale", selection: $settings.scale) {
                        ForEach(MockupScale.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                    .accessibilityLabel("Scale")
                }
            } footer: {
                Text("Difference draws black where the app matches the mockup and bright where it drifts.")
            }
        }
    }
#endif
