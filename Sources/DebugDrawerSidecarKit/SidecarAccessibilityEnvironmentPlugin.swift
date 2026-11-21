import DebugDrawer
import DebugDrawerAccessibility
import Foundation
import SwiftUI

// The sidecar's half of accessibility environment overrides (DD-123): Dynamic Type, Increase
// Contrast and Reduce Motion in the app's SwiftUI views (`AccessibilityEnvironmentOverrides`, in
// DebugDrawerAccessibility), each the system's or overridden, with Reset while any is, back to the
// system's as the session ends. It ships in the kit, as the settings are the library's own, so
// every sidecar would draw the same pickers.

#if DEBUG
    extension DebugDrawerSidecarPlugin {
        /// Dynamic Type, Increase Contrast and Reduce Motion in the app's SwiftUI views
        /// (`DebugDrawerReceiverCapability.accessibilityEnvironmentOverrides(_:)`), each the system's
        /// or overridden for the session, with Reset.
        @MainActor public static var accessibilityEnvironmentOverrides: DebugDrawerSidecarPlugin {
            DebugDrawerSidecarPlugin(
                id: AccessibilityEnvironmentOverrides.pluginID, title: "Accessibility", icon: "accessibility",
                snapshot: AccessibilityEnvironmentOverrides.Snapshot.self, command: AccessibilityEnvironmentOverrides.Command.self
            ) { transport in
                AccessibilityEnvironmentSidecarPlugin(transport: transport)
            }
        }
    }

    /// The app's accessibility overrides, set from the sidecar.
    struct AccessibilityEnvironmentSidecarPlugin: DebugDrawerPlugin {
        let transport: DebugDrawerPluginTransport<AccessibilityEnvironmentOverrides.Snapshot, AccessibilityEnvironmentOverrides.Command>
        let title = "Accessibility"
        let icon = "accessibility"

        var body: some View {
            AccessibilityEnvironmentTransportView(transport: transport)
        }
    }

    /// The overrides over the capability's snapshot, sending what the view asks.
    struct AccessibilityEnvironmentTransportView: View {
        @ObservedObject var transport: DebugDrawerPluginTransport<
            AccessibilityEnvironmentOverrides.Snapshot, AccessibilityEnvironmentOverrides.Command
        >

        var body: some View {
            AccessibilityEnvironmentView(snapshot: transport.snapshot) { transport.send($0) }
        }
    }

    /// A picker for each setting, the system's or an override, and Reset while any is overridden. A
    /// function of the snapshot and the send action.
    struct AccessibilityEnvironmentView: View {
        let snapshot: AccessibilityEnvironmentOverrides.Snapshot
        let send: (AccessibilityEnvironmentOverrides.Command) -> Void

        var body: some View {
            DebugDrawerSection("Overrides") {
                DebugDrawerRow("Dynamic Type") {
                    Picker("Dynamic Type", selection: Binding { snapshot.dynamicTypeSize } set: { send(.setDynamicTypeSize($0)) }) {
                        Text("System").tag(AccessibilityEnvironmentOverrides.DynamicTypeSize?.none)
                        ForEach(AccessibilityEnvironmentOverrides.DynamicTypeSize.allCases, id: \.self) { size in
                            Text(size.title).tag(Optional(size))
                        }
                    }
                    .labelsHidden()
                    .accessibilityLabel("Dynamic Type")
                }
                .accessibilityIdentifier("Accessibility-DynamicType")
                SystemOrBooleanRow(title: "Increase Contrast", value: snapshot.increaseContrast) { send(.setIncreaseContrast($0)) }
                    .accessibilityIdentifier("Accessibility-IncreaseContrast")
                SystemOrBooleanRow(title: "Reduce Motion", value: snapshot.reduceMotion) { send(.setReduceMotion($0)) }
                    .accessibilityIdentifier("Accessibility-ReduceMotion")
                if snapshot != AccessibilityEnvironmentOverrides.Snapshot() {
                    DebugDrawerActionRow {
                        Button("Reset") { send(.reset) }
                            .debugDrawerButtonStyle(.secondary)
                            .accessibilityLabel("Reset")
                            .accessibilityHint("Every setting is the system's again")
                    }
                }
            } footer: {
                Text("Applies to the app's SwiftUI views; back to the system's settings as the session ends.")
            }
        }
    }

    /// A setting that is the system's, on or off.
    struct SystemOrBooleanRow: View {
        let title: String
        let value: Bool?
        let set: (Bool?) -> Void

        var body: some View {
            DebugDrawerRow(title) {
                Picker(title, selection: Binding { value } set: { set($0) }) {
                    Text("System").tag(Bool?.none)
                    Text("On").tag(Bool?.some(true))
                    Text("Off").tag(Bool?.some(false))
                }
                .labelsHidden()
                .accessibilityLabel(title)
            }
        }
    }

    extension AccessibilityEnvironmentOverrides.DynamicTypeSize {
        /// The size as Settings names it.
        fileprivate var title: String {
            switch self {
            case .xSmall: "Extra Small"
            case .small: "Small"
            case .medium: "Medium"
            case .large: "Large (Default)"
            case .xLarge: "Extra Large"
            case .xxLarge: "Extra Extra Large"
            case .xxxLarge: "Extra Extra Extra Large"
            case .accessibility1: "Accessibility 1"
            case .accessibility2: "Accessibility 2"
            case .accessibility3: "Accessibility 3"
            case .accessibility4: "Accessibility 4"
            case .accessibility5: "Accessibility 5"
            }
        }
    }
#else
    // The release stand-in: the same member, over a plugin that draws nothing; a release build's
    // transports connect to nothing anyway.

    extension DebugDrawerSidecarPlugin {
        /// The app's accessibility overrides; release builds show nothing.
        @MainActor public static var accessibilityEnvironmentOverrides: DebugDrawerSidecarPlugin {
            DebugDrawerSidecarPlugin(
                id: AccessibilityEnvironmentOverrides.pluginID, title: "Accessibility", icon: "accessibility",
                snapshot: AccessibilityEnvironmentOverrides.Snapshot.self, command: AccessibilityEnvironmentOverrides.Command.self
            ) { _ in
                AccessibilityEnvironmentSidecarPlugin()
            }
        }
    }

    /// Draws nothing.
    struct AccessibilityEnvironmentSidecarPlugin: DebugDrawerPlugin {
        let title = "Accessibility"
        let icon = "accessibility"

        var body: some View {
            EmptyView()
        }
    }
#endif
