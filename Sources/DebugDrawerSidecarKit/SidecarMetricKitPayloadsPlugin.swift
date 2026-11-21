import DebugDrawer
#if canImport(DebugDrawerMetricKit)
    import DebugDrawerMetricKit
#endif
import Foundation
import SwiftUI

// The sidecar's half of MetricKit forwarding (DD-114): the payloads the app keeps
// (`MetricKitPayloadsMirror`, in DebugDrawerMetricKit), crash diagnostics among them, newest
// first and redacted in the app, each with its JSON to copy and Delete, and Delete All. It ships in
// the kit, as the payloads describe themselves, so every sidecar would draw the same list. It is a
// `DebugDrawerReportContributor`, so Create Report adds each payload as JSON. DebugDrawerMetricKit
// doesn't build for watchOS, so the kit has no `metricKitPayloads` there
// (PLATFORM_CONDITIONAL_DEPENDENCIES in scripts/modules.py).

#if DEBUG && canImport(DebugDrawerMetricKit)
    extension DebugDrawerSidecarPlugin {
        /// The MetricKit payloads the app keeps, crash diagnostics among them
        /// (`DebugDrawerReceiverCapability.metricKitPayloads(sessions:directory:redaction:capacity:)`),
        /// newest first, each with its JSON to copy and Delete; Create Report adds them.
        @MainActor public static var metricKitPayloads: DebugDrawerSidecarPlugin {
            DebugDrawerSidecarPlugin(
                id: MetricKitPayloadsMirror.pluginID, title: "MetricKit", icon: "waveform.path.ecg",
                snapshot: MetricKitPayloadsMirror.Snapshot.self, command: MetricKitPayloadsMirror.Command.self
            ) { transport in
                MetricKitPayloadsSidecarPlugin(transport: transport)
            }
        }
    }

    /// The app's MetricKit payloads, shown in the sidecar.
    struct MetricKitPayloadsSidecarPlugin: DebugDrawerPlugin, DebugDrawerReportContributor {
        let transport: DebugDrawerPluginTransport<MetricKitPayloadsMirror.Snapshot, MetricKitPayloadsMirror.Command>
        let title = "MetricKit"
        let icon = "waveform.path.ecg"

        var body: some View {
            MetricKitPayloadsTransportView(transport: transport)
        }

        /// Adds each payload, as the app redacted it, named for its kind and the end of the period
        /// it covers (`diagnostics-2026-11-20T080000Z.json`).
        func contribute(to report: inout DebugDrawerReport, redaction _: DebugDrawerRedaction) {
            for payload in transport.snapshot.payloads {
                report.add(jsonData: payload.json, named: payload.reportName)
            }
        }
    }

    /// The payloads over the capability's snapshot, sending what the view asks.
    struct MetricKitPayloadsTransportView: View {
        @ObservedObject var transport: DebugDrawerPluginTransport<MetricKitPayloadsMirror.Snapshot, MetricKitPayloadsMirror.Command>

        var body: some View {
            MetricKitPayloadsView(snapshot: transport.snapshot) { transport.send($0) }
        }
    }

    /// The payloads, newest first, each with Copy JSON and Delete, and Delete All; or why there
    /// are none. A function of the snapshot and the send action.
    struct MetricKitPayloadsView: View {
        let snapshot: MetricKitPayloadsMirror.Snapshot
        let send: (MetricKitPayloadsMirror.Command) -> Void

        var body: some View {
            if snapshot.payloads.isEmpty {
                DebugDrawerEmptyState("No Payloads", systemImage: "waveform.path.ecg") {
                    Text(
                        snapshot.sessionID == nil
                            ? "The app shows the payloads it keeps only while a session is open."
                            : "MetricKit hands the app its payloads on a device: a crash diagnostic on the launch after a crash."
                    )
                }
            } else {
                DebugDrawerSection("Payloads") {
                    ForEach(snapshot.payloads) { payload in
                        DebugDrawerRow(payload.kind.title) {
                            Text("\(payload.begin.formatted()) – \(payload.end.formatted())")
                            DebugDrawerActionRow {
                                DebugDrawerCopyButton("Copy JSON") { String(bytes: payload.json, encoding: .utf8) }
                                Button("Delete", role: .destructive) { send(.delete(id: payload.id)) }
                                    .debugDrawerButtonStyle(.destructive)
                                    .accessibilityLabel("Delete \(payload.kind.title) payload")
                            }
                        } accessory: {
                            Text(payload.json.count.formatted(.byteCount(style: .file)))
                                .debugDrawerFont(.value)
                        }
                        .accessibilityIdentifier("MetricKitPayload-\(payload.id.uuidString)")
                    }
                } footer: {
                    Text("Redacted in the app; a deleted payload doesn't come back when MetricKit delivers it again.")
                }
                DebugDrawerActionRow {
                    EmptyView()
                } trailing: {
                    Button("Delete All", role: .destructive) { send(.deleteAll) }
                        .debugDrawerButtonStyle(.destructive)
                        .accessibilityLabel("Delete All")
                        .accessibilityHint("Deletes every payload the app keeps")
                }
            }
        }
    }

    extension MetricKitPayloadKind {
        /// The kind as a row names it.
        fileprivate var title: String {
            switch self {
            case .metrics: "Metrics"
            case .diagnostics: "Diagnostics"
            }
        }
    }

    extension MetricKitPayloadsMirror.Payload {
        /// The file name the report gives it: its kind and the end of its period, in UTC.
        fileprivate var reportName: String {
            "\(kind.rawValue)-\(end.formatted(Date.ISO8601FormatStyle(timeSeparator: .omitted)))"
        }
    }
#elseif canImport(DebugDrawerMetricKit)
    // The release stand-in: the same member, over a plugin that draws nothing; a release build's
    // transports connect to nothing anyway.

    extension DebugDrawerSidecarPlugin {
        /// The MetricKit payloads the app keeps; release builds show nothing.
        @MainActor public static var metricKitPayloads: DebugDrawerSidecarPlugin {
            DebugDrawerSidecarPlugin(
                id: MetricKitPayloadsMirror.pluginID, title: "MetricKit", icon: "waveform.path.ecg",
                snapshot: MetricKitPayloadsMirror.Snapshot.self, command: MetricKitPayloadsMirror.Command.self
            ) { _ in
                MetricKitPayloadsSidecarPlugin()
            }
        }
    }

    /// Draws nothing.
    struct MetricKitPayloadsSidecarPlugin: DebugDrawerPlugin {
        let title = "MetricKit"
        let icon = "waveform.path.ecg"

        var body: some View {
            EmptyView()
        }
    }
#endif
