import DebugDrawer
import DebugDrawerAppInfo
import Foundation
import SwiftUI

// The sidecar's half of the app state capability (DD-126): the build, and each field the host
// registered, read-only, with Refresh. It ships in the kit, as every sidecar would draw the same
// rows, and it is a `DebugDrawerReportContributor` that the connected screen hosts as the app is
// reached (`hostsOnConnect`), so Create Report attaches `app-state.json` whether or not the
// employee opened it. The JSON goes through the sidecar's redaction like every other file, so a
// host value under a masked key ("email") is masked in the report too.

#if DEBUG
    extension DebugDrawerSidecarPlugin {
        /// The app's state (`DebugDrawerReceiverCapability.appState(_:)`): the version, build,
        /// commit, branch and CI build, and each field the host registered (its flag and
        /// experiment overrides, experiment buckets, environment, hashed user ID and values), with
        /// Refresh. The sidecar view hosts it as the app is reached, so every report carries
        /// `app-state.json`.
        @MainActor public static var appState: DebugDrawerSidecarPlugin {
            var plugin = DebugDrawerSidecarPlugin(
                id: DebugDrawerAppState.pluginID, title: "App State", icon: "list.bullet.rectangle",
                snapshot: DebugDrawerAppState.Snapshot.self, command: DebugDrawerAppState.Command.self
            ) { transport in
                AppStatePlugin(transport: transport)
            }
            plugin.hostsOnConnect = true
            return plugin
        }
    }

    /// The app's state, shown in the sidecar and attached to its reports.
    struct AppStatePlugin: DebugDrawerPlugin, DebugDrawerReportContributor {
        let transport: DebugDrawerPluginTransport<DebugDrawerAppState.Snapshot, DebugDrawerAppState.Command>
        let title = "App State"
        let icon = "list.bullet.rectangle"

        var body: some View {
            AppStateTransportView(transport: transport)
        }

        /// Adds `app-state.json`: the state as last read, redacted with the report's rules. Nothing
        /// while no session serves it.
        func contribute(to report: inout DebugDrawerReport, redaction: DebugDrawerRedaction) {
            guard let state = transport.snapshot.state, let json = state.reportJSON else { return }
            report.add(jsonData: redaction.redacting(json: json), named: "app-state")
        }
    }

    extension DebugDrawerAppState.State {
        /// The state as pretty JSON with sorted keys and ISO 8601 dates, as the report's other
        /// JSON files are.
        fileprivate var reportJSON: Data? {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            return try? encoder.encode(self)
        }
    }

    /// The state over the capability's snapshot, sending what the view asks.
    struct AppStateTransportView: View {
        @ObservedObject var transport: DebugDrawerPluginTransport<DebugDrawerAppState.Snapshot, DebugDrawerAppState.Command>

        var body: some View {
            AppStateView(snapshot: transport.snapshot) { transport.send($0) }
        }
    }

    /// The build, each registered field, and Refresh; outside a session, why there is nothing. A
    /// function of the snapshot and the send action.
    struct AppStateView: View {
        let snapshot: DebugDrawerAppState.Snapshot
        let send: (DebugDrawerAppState.Command) -> Void

        var body: some View {
            if let state = snapshot.state {
                AppStateSections(state: state)
                DebugDrawerActionRow {
                    Button("Refresh") { send(.refresh) }
                        .debugDrawerButtonStyle(.secondary)
                        .accessibilityLabel("Refresh App State")
                }
            } else {
                DebugDrawerEmptyState("No App State", systemImage: "list.bullet.rectangle") {
                    Text("The app shows its state during a session. Open one to read it.")
                }
            }
        }
    }

    /// The state's sections: Build always, then each field the host registered.
    struct AppStateSections: View {
        let state: DebugDrawerAppState.State

        var body: some View {
            DebugDrawerSection("Build") {
                DebugDrawerKeyValueRow("Bundle ID", value: state.bundleIdentifier)
                DebugDrawerKeyValueRow("Version", value: state.version.isEmpty ? "—" : state.version)
                DebugDrawerKeyValueRow("Build", value: state.build.isEmpty ? "—" : state.build)
                DebugDrawerKeyValueRow("Commit", value: state.buildMetadata.gitCommit ?? "—")
                DebugDrawerKeyValueRow("Branch", value: state.buildMetadata.gitBranch ?? "—")
                DebugDrawerKeyValueRow("CI Build", value: state.buildMetadata.ciBuildNumber ?? "—")
                DebugDrawerKeyValueRow("Read", value: state.date.formatted(date: .omitted, time: .standard))
            }
            if let environment = state.environment {
                DebugDrawerSection("Environment") {
                    DebugDrawerKeyValueRow(
                        "Active", value: environment.isSwitched ? "\(environment.title) (switched)" : environment.title
                    )
                }
            }
            if let hashedUserID = state.hashedUserID {
                DebugDrawerSection("User") {
                    DebugDrawerKeyValueRow("Hashed ID", value: hashedUserID)
                    DebugDrawerActionRow {
                        DebugDrawerCopyButton("Copy Hashed ID") { hashedUserID }
                    }
                }
            }
            if let overrides = state.featureFlagOverrides {
                DebugDrawerSection("Flag Overrides") {
                    if overrides.isEmpty {
                        Text("None").debugDrawerFont(.label).debugDrawerRowPadding()
                    }
                    ForEach(overrides.keys.sorted(), id: \.self) { key in
                        DebugDrawerKeyValueRow(key, value: overrides[key]?.text ?? "")
                    }
                }
            }
            if let experiments = state.experiments {
                DebugDrawerSection("Experiments") {
                    if experiments.isEmpty {
                        Text("None").debugDrawerFont(.label).debugDrawerRowPadding()
                    }
                    ForEach(experiments.keys.sorted(), id: \.self) { key in
                        DebugDrawerKeyValueRow(key, value: experiments[key]?.text ?? "")
                    }
                }
            }
            if let values = state.values {
                DebugDrawerSection("Values") {
                    if values.isEmpty {
                        Text("None").debugDrawerFont(.label).debugDrawerRowPadding()
                    }
                    ForEach(values.keys.sorted(), id: \.self) { key in
                        DebugDrawerKeyValueRow(key, value: values[key]?.text ?? "")
                    }
                }
            }
        }
    }

    extension DebugDrawerFeatureFlagValue {
        /// The value as its row shows it.
        fileprivate var text: String {
            switch self {
            case let .bool(value): value ? "On" : "Off"
            case let .number(value): value.wholeText
            case let .string(value): value
            }
        }
    }

    extension DebugDrawerAppStateValue {
        /// The value as its row shows it.
        fileprivate var text: String {
            switch self {
            case let .string(value): value
            case let .number(value): value.wholeText
            case let .bool(value): value ? "Yes" : "No"
            }
        }
    }

    extension DebugDrawerAppState.ExperimentBucket {
        /// The bucket, marked when a sidecar forced it.
        fileprivate var text: String {
            let bucket = variant ?? "Not enrolled"
            return isOverridden ? "\(bucket) (overridden)" : bucket
        }
    }

    extension Double {
        /// A whole number without a fraction (`3`, not `3.0`), others as Swift writes them.
        fileprivate var wholeText: String {
            rounded() == self && abs(self) < 1e15 ? String(Int64(self)) : String(self)
        }
    }
#else
    // The release stand-in: the same member, over a plugin that draws nothing; a release build's
    // transports connect to nothing anyway.

    extension DebugDrawerSidecarPlugin {
        /// The app's state; release builds show nothing.
        @MainActor public static var appState: DebugDrawerSidecarPlugin {
            DebugDrawerSidecarPlugin(
                id: DebugDrawerAppState.pluginID, title: "App State", icon: "list.bullet.rectangle",
                snapshot: DebugDrawerAppState.Snapshot.self, command: DebugDrawerAppState.Command.self
            ) { _ in
                AppStatePlugin()
            }
        }
    }

    /// Draws nothing.
    struct AppStatePlugin: DebugDrawerPlugin {
        let title = "App State"
        let icon = "list.bullet.rectangle"

        var body: some View {
            EmptyView()
        }
    }
#endif
