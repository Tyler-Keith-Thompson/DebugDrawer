import DebugDrawer
import DebugDrawerSidecarKit
import SwiftUI

extension DebugDrawerSidecarPlugin {
    /// The host's feature flags (`DebugDrawerReceiverCapability.featureFlagOverrides`), each
    /// overridden for the session.
    @MainActor static var featureFlagOverrides: DebugDrawerSidecarPlugin {
        DebugDrawerSidecarPlugin(
            id: DebugDrawerFeatureFlagOverrides.pluginID, title: "Flags", icon: "flag",
            snapshot: DebugDrawerFeatureFlagOverrides.Snapshot.self, command: DebugDrawerFeatureFlagOverrides.Command.self
        ) { transport in
            FeatureFlagOverridesPlugin(transport: transport)
        }
    }
}

/// The host's flags: a switch for each Boolean, a field for each other value, and Clear All.
struct FeatureFlagOverridesPlugin: DebugDrawerPlugin {
    let transport: DebugDrawerPluginTransport<DebugDrawerFeatureFlagOverrides.Snapshot, DebugDrawerFeatureFlagOverrides.Command>
    let title = "Flags"
    let icon = "flag"

    var body: some View {
        FeatureFlagOverridesView(transport: transport)
    }
}

private struct FeatureFlagOverridesView: View {
    @ObservedObject var transport: DebugDrawerPluginTransport<DebugDrawerFeatureFlagOverrides.Snapshot, DebugDrawerFeatureFlagOverrides.Command>

    var body: some View {
        DebugDrawerSection("Flags") {
            ForEach(transport.snapshot.flags, id: \.key) { flag in
                switch flag.value {
                case let .bool(isOn):
                    DebugDrawerRow(flag.key, isOn: Binding(
                        get: { isOn },
                        set: { transport.send(.setOverride(key: flag.key, value: .bool($0))) }
                    ))
                case let .number(value):
                    FlagTextRow(key: flag.key, value: value.formatted()) { text in
                        Double(text).map { .number($0) }
                    } send: { transport.send($0) }
                case let .string(value):
                    FlagTextRow(key: flag.key, value: value) { .string($0) } send: { transport.send($0) }
                }
            }
        } footer: {
            Text("Overridden: \(transport.snapshot.overriddenKeys.isEmpty ? "none" : transport.snapshot.overriddenKeys.joined(separator: ", "))")
        }
        DebugDrawerActionRow {
            Button("Clear All Overrides") { transport.send(.clearAllOverrides) }
        }
    }
}

/// A flag whose value is typed: sent as the person submits it.
private struct FlagTextRow: View {
    let key: String
    let value: String
    let parse: (String) -> DebugDrawerFeatureFlagValue?
    let send: (DebugDrawerFeatureFlagOverrides.Command) -> Void
    @State private var text = ""

    var body: some View {
        DebugDrawerRow(key) {
            TextField(key, text: $text)
                .debugDrawerTextFieldStyle()
                .accessibilityLabel(key)
                .onSubmit {
                    if let parsed = parse(text) {
                        send(.setOverride(key: key, value: parsed))
                    }
                }
                .onChange(of: value, initial: true) { _, value in text = value }
        }
    }
}
