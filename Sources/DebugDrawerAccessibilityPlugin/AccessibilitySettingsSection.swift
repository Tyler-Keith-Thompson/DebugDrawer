#if DEBUG
    import DebugDrawer
    import SwiftUI

    // MARK: - System accessibility settings

    /// A row per system accessibility setting: its name, the system's value, and a System/On/Off override.
    struct AccessibilitySettingsSection: View {
        struct SystemValues: Equatable {
            var reduceMotion = false
            var increaseContrast = false
            var boldText = false
            var reduceTransparency = false
            var differentiateWithoutColor = false
            var invertColors = false
        }

        let system: SystemValues
        @ObservedObject var overrides = AccessibilityOverrides.shared

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                row("Reduce Motion", system: system.reduceMotion, override: $overrides.reduceMotion)
                row("Increase Contrast", system: system.increaseContrast, override: $overrides.increaseContrast)
                row("Bold Text", system: system.boldText, override: $overrides.boldText)
                row("Reduce Transparency", system: system.reduceTransparency,
                    override: $overrides.reduceTransparency)
                row("Differentiate Without Color", system: system.differentiateWithoutColor,
                    override: $overrides.differentiateWithoutColor)
                row("Invert Colors", system: system.invertColors, override: $overrides.invertColors)
            }
        }

        // DebugDrawerRow moves the picker below the name at accessibility text sizes.
        private func row(_ title: String, system: Bool, override: Binding<Bool?>) -> some View {
            DebugDrawerRow(title) {
                Text("System: \(system ? "On" : "Off")")
            } accessory: {
                Picker(title, selection: Binding(
                    get: { override.wrappedValue.map { $0 ? 1 : 2 } ?? 0 },
                    set: { override.wrappedValue = $0 == 0 ? nil : $0 == 1 }
                )) {
                    Text("System").tag(0)
                    Text("On").tag(1)
                    Text("Off").tag(2)
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .accessibilityLabel(title)
                .accessibilityElement(children: .contain)
            }
        }
    }
#endif
