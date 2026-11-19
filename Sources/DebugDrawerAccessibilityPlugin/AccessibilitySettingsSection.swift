#if DEBUG
    import DebugDrawer
    import SwiftUI

    // MARK: - System accessibility settings

    /// A row per system accessibility setting: its name, the system's value, and a System/On/Off override.
    struct AccessibilitySettingsSection: View {
        let system: AccessibilitySystemValues
        @ObservedObject var transport: DebugDrawerPluginTransport<AccessibilitySnapshot, AccessibilityCommand>

        /// - Parameters:
        ///   - system: The system's value of each setting, shown beside its override.
        ///   - transport: The model whose overrides the pickers show and set.
        init(
            system: AccessibilitySystemValues,
            transport: DebugDrawerPluginTransport<AccessibilitySnapshot, AccessibilityCommand> = .direct(to: AccessibilityModel())
        ) {
            self.system = system
            _transport = ObservedObject(wrappedValue: transport)
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                row(.reduceMotion)
                row(.increaseContrast)
                row(.boldText)
                row(.reduceTransparency)
                row(.differentiateWithoutColor)
                row(.invertColors)
            }
        }

        // DebugDrawerRow moves the picker below the name at accessibility text sizes.
        private func row(_ setting: AccessibilitySetting) -> some View {
            DebugDrawerRow(setting.title) {
                Text("System: \(system[setting] ? "On" : "Off")")
            } accessory: {
                Picker(setting.title, selection: Binding(
                    get: { transport.snapshot.overrides[setting].map { $0 ? 1 : 2 } ?? 0 },
                    set: { transport.send(AccessibilityCommand(.setSetting(setting, $0 == 0 ? nil : $0 == 1))) }
                )) {
                    Text("System").tag(0)
                    Text("On").tag(1)
                    Text("Off").tag(2)
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .accessibilityLabel(setting.title)
                .accessibilityElement(children: .contain)
            }
        }
    }

    extension AccessibilitySetting {
        /// The setting's name, as the system's settings call it.
        var title: String {
            switch self {
            case .reduceMotion: "Reduce Motion"
            case .increaseContrast: "Increase Contrast"
            case .boldText: "Bold Text"
            case .reduceTransparency: "Reduce Transparency"
            case .differentiateWithoutColor: "Differentiate Without Color"
            case .invertColors: "Invert Colors"
            }
        }
    }
#endif
