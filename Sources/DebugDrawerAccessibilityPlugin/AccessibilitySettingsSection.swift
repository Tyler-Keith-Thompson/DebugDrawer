#if DEBUG
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
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
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

        // At accessibility text sizes the name and the picker don't fit side by side, so the
        // picker sits below the name.
        private func row(_ title: String, system: Bool, override: Binding<Bool?>) -> some View {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                : AnyLayout(HStackLayout(spacing: 6))
            return layout {
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.caption2)
                    Text("System: \(system ? "On" : "Off")")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                if !dynamicTypeSize.isAccessibilitySize {
                    Spacer()
                }
                Picker(title, selection: Binding(
                    get: { override.wrappedValue.map { $0 ? 1 : 2 } ?? 0 },
                    set: { override.wrappedValue = $0 == 0 ? nil : $0 == 1 }
                )) {
                    Text("System").tag(0)
                    Text("On").tag(1)
                    Text("Off").tag(2)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.mini)
                .fixedSize()
                .accessibilityLabel(title)
                .accessibilityElement(children: .contain)
            }
        }
    }
#endif
