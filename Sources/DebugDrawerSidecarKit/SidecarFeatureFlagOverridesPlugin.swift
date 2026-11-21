import DebugDrawer
import Foundation
import SwiftUI

// The sidecar's half of feature flag overrides (DD-92, DD-108): the flags the app's adapter lists
// (`DebugDrawerFeatureFlagOverrides`, in the receiver), each with an editor for its kind (a switch
// for a Boolean, a field and Set for a number or a string), Clear for an overridden flag, and Clear
// All Overrides while any is. It ships in the kit, as each flag's value says its kind, so every
// sidecar would draw the same editors. A field sends only once Set is pressed, and only a value of
// the flag's own kind, as the receiver refuses any other (`malformedCommand`).

#if DEBUG
    extension DebugDrawerSidecarPlugin {
        /// The feature flags the app's adapter lists (`DebugDrawerReceiverCapability.featureFlagOverrides(_:)`),
        /// each with an editor for its kind and Clear once overridden, and Clear All Overrides.
        @MainActor public static var featureFlagOverrides: DebugDrawerSidecarPlugin {
            DebugDrawerSidecarPlugin(
                id: DebugDrawerFeatureFlagOverrides.pluginID, title: "Flags", icon: "flag",
                snapshot: DebugDrawerFeatureFlagOverrides.Snapshot.self, command: DebugDrawerFeatureFlagOverrides.Command.self
            ) { transport in
                FeatureFlagOverridesSidecarPlugin(transport: transport)
            }
        }
    }

    /// The app's feature flags, overridden from the sidecar.
    struct FeatureFlagOverridesSidecarPlugin: DebugDrawerPlugin {
        let transport: DebugDrawerPluginTransport<DebugDrawerFeatureFlagOverrides.Snapshot, DebugDrawerFeatureFlagOverrides.Command>
        let title = "Flags"
        let icon = "flag"

        var body: some View {
            FeatureFlagOverridesTransportView(transport: transport)
        }
    }

    /// The flags over the capability's snapshot, sending what the view asks.
    struct FeatureFlagOverridesTransportView: View {
        @ObservedObject var transport: DebugDrawerPluginTransport<DebugDrawerFeatureFlagOverrides.Snapshot, DebugDrawerFeatureFlagOverrides.Command>

        var body: some View {
            FeatureFlagOverridesView(snapshot: transport.snapshot) { transport.send($0) }
        }
    }

    /// Each flag with its editor, and Clear All Overrides while any flag is overridden. A function
    /// of the snapshot and the send action.
    struct FeatureFlagOverridesView: View {
        let snapshot: DebugDrawerFeatureFlagOverrides.Snapshot
        let send: (DebugDrawerFeatureFlagOverrides.Command) -> Void

        var body: some View {
            if snapshot.flags.isEmpty {
                DebugDrawerEmptyState("No Flags", systemImage: "flag") {
                    Text("The app's adapter lists no flag a sidecar may override.")
                }
            } else {
                DebugDrawerSection("Flags") {
                    ForEach(snapshot.flags, id: \.key) { flag in
                        FeatureFlagOverrideRow(flag: flag, isOverridden: snapshot.overriddenKeys.contains(flag.key), send: send)
                    }
                    if !snapshot.overriddenKeys.isEmpty {
                        DebugDrawerActionRow {
                            Button("Clear All Overrides") { send(.clearAllOverrides) }
                                .debugDrawerButtonStyle(.secondary)
                                .accessibilityLabel("Clear All Overrides")
                                .accessibilityHint("The app reads every flag from its own service again")
                        }
                    }
                } footer: {
                    Text("Overrides are cleared as the session ends.")
                }
            }
        }
    }

    /// One flag: its key, its value, and the editor its kind takes.
    struct FeatureFlagOverrideRow: View {
        let flag: DebugDrawerFeatureFlag
        let isOverridden: Bool
        let send: (DebugDrawerFeatureFlagOverrides.Command) -> Void
        @State private var draft: String

        init(flag: DebugDrawerFeatureFlag, isOverridden: Bool, send: @escaping (DebugDrawerFeatureFlagOverrides.Command) -> Void) {
            self.flag = flag
            self.isOverridden = isOverridden
            self.send = send
            _draft = State(initialValue: flag.value.draftText)
        }

        var body: some View {
            Group {
                switch flag.value {
                case let .bool(isOn):
                    DebugDrawerRow(flag.key, systemImage: nil, details: { details }, accessory: {
                        Toggle(isOn: Binding { isOn } set: { send(.setOverride(key: flag.key, value: .bool($0))) }) {
                            Text(flag.key)
                        }
                        .labelsHidden()
                        .accessibilityLabel(flag.key)
                    })
                case .number, .string:
                    DebugDrawerRow(flag.key, systemImage: nil, details: { details }, accessory: {
                        HStack(spacing: 6) {
                            TextField(flag.key, text: $draft)
                                .debugDrawerTextFieldStyle()
                                .accessibilityLabel(flag.key)
                            Button("Set") {
                                if let value = flag.value.sameKind(from: draft) {
                                    send(.setOverride(key: flag.key, value: value))
                                }
                            }
                            .debugDrawerButtonStyle(.primary)
                            .disabled(flag.value.sameKind(from: draft) == nil || flag.value.sameKind(from: draft) == flag.value)
                            .accessibilityLabel("Set \(flag.key)")
                        }
                    })
                }
            }
            .onChange(of: flag.value) { _, value in
                draft = value.draftText
            }
            .accessibilityIdentifier("Flag-\(flag.key)")
        }

        @ViewBuilder
        private var details: some View {
            Text(flag.value.summary)
            if isOverridden {
                Text("Overridden")
                    .debugDrawerForegroundStyle(.accent)
                Button("Clear") { send(.clearOverride(key: flag.key)) }
                    .debugDrawerButtonStyle(.secondary)
                    .accessibilityLabel("Clear \(flag.key)")
                    .accessibilityHint("The app reads the flag from its own service again")
            }
        }
    }

    extension DebugDrawerFeatureFlagValue {
        /// The value as a text field starts at.
        fileprivate var draftText: String {
            switch self {
            case let .bool(isOn): isOn ? "true" : "false"
            case let .number(number): number.formatted(.number.grouping(.never))
            case let .string(text): text
            }
        }

        /// The value as the row says it.
        fileprivate var summary: String {
            switch self {
            case let .bool(isOn): isOn ? "On" : "Off"
            case let .number(number): number.formatted()
            case let .string(text): "\"\(text)\""
            }
        }

        /// A value of this one's kind read from `text`, or `nil` when the text isn't one: the
        /// receiver refuses an override of another kind.
        func sameKind(from text: String) -> Self? {
            switch self {
            case .bool: nil
            case .number: Double(text.trimmingCharacters(in: .whitespaces)).flatMap { $0.isFinite ? .number($0) : nil }
            case .string: .string(text)
            }
        }
    }
#else
    // The release stand-in: the same member, over a plugin that draws nothing; a release build's
    // transports connect to nothing anyway.

    extension DebugDrawerSidecarPlugin {
        /// The feature flags the app's adapter lists; release builds show nothing.
        @MainActor public static var featureFlagOverrides: DebugDrawerSidecarPlugin {
            DebugDrawerSidecarPlugin(
                id: DebugDrawerFeatureFlagOverrides.pluginID, title: "Flags", icon: "flag",
                snapshot: DebugDrawerFeatureFlagOverrides.Snapshot.self, command: DebugDrawerFeatureFlagOverrides.Command.self
            ) { _ in
                FeatureFlagOverridesSidecarPlugin()
            }
        }
    }

    /// Draws nothing.
    struct FeatureFlagOverridesSidecarPlugin: DebugDrawerPlugin {
        let title = "Flags"
        let icon = "flag"

        var body: some View {
            EmptyView()
        }
    }
#endif
