import DebugDrawer
import DebugDrawerAccessibility
import DebugDrawerSidecarKit
import SwiftUI

extension DebugDrawerSidecarPlugin {
    /// The host's accessibility overrides (`DebugDrawerReceiverCapability.accessibilityEnvironmentOverrides`).
    @MainActor static var accessibilityEnvironment: DebugDrawerSidecarPlugin {
        DebugDrawerSidecarPlugin(
            id: AccessibilityEnvironmentOverrides.pluginID, title: "Accessibility", icon: "accessibility",
            snapshot: AccessibilityEnvironmentOverrides.Snapshot.self, command: AccessibilityEnvironmentOverrides.Command.self
        ) { transport in
            AccessibilityEnvironmentPlugin(transport: transport)
        }
    }
}

/// Dynamic Type, Increase Contrast and Reduce Motion in the host's window, for the session.
struct AccessibilityEnvironmentPlugin: DebugDrawerPlugin {
    let transport: DebugDrawerPluginTransport<AccessibilityEnvironmentOverrides.Snapshot, AccessibilityEnvironmentOverrides.Command>
    let title = "Accessibility"
    let icon = "accessibility"

    var body: some View {
        AccessibilityEnvironmentView(transport: transport)
    }
}

private struct AccessibilityEnvironmentView: View {
    @ObservedObject var transport: DebugDrawerPluginTransport<AccessibilityEnvironmentOverrides.Snapshot, AccessibilityEnvironmentOverrides.Command>

    var body: some View {
        DebugDrawerSection("Overrides") {
            DebugDrawerRow("Dynamic Type") {
                Picker("Dynamic Type", selection: Binding(
                    get: { transport.snapshot.dynamicTypeSize },
                    set: { transport.send(.setDynamicTypeSize($0)) }
                )) {
                    Text("System").tag(AccessibilityEnvironmentOverrides.DynamicTypeSize?.none)
                    ForEach(AccessibilityEnvironmentOverrides.DynamicTypeSize.allCases, id: \.self) { size in
                        Text(size.rawValue).tag(Optional(size))
                    }
                }
                .labelsHidden()
            }
            SystemOrBoolRow(title: "Increase Contrast", value: transport.snapshot.increaseContrast) {
                transport.send(.setIncreaseContrast($0))
            }
            SystemOrBoolRow(title: "Reduce Motion", value: transport.snapshot.reduceMotion) {
                transport.send(.setReduceMotion($0))
            }
        } footer: {
            Text("Back to the system's settings as the session ends.")
        }
        DebugDrawerActionRow {
            Button("Reset") { transport.send(.reset) }
        }
    }
}

/// A setting that is the system's, on or off.
private struct SystemOrBoolRow: View {
    let title: String
    let value: Bool?
    let set: @MainActor @Sendable (Bool?) -> Void

    var body: some View {
        DebugDrawerRow(title) {
            Picker(title, selection: Binding(get: { value }, set: set)) {
                Text("System").tag(Bool?.none)
                Text("On").tag(Bool?.some(true))
                Text("Off").tag(Bool?.some(false))
            }
            .labelsHidden()
            .accessibilityLabel(title)
        }
    }
}
