import DebugDrawer
import DebugDrawerMetricKit
import DebugDrawerSidecarKit
import SwiftUI

extension DebugDrawerSidecarPlugin {
    /// The MetricKit payloads the host keeps, crash diagnostics among them
    /// (`DebugDrawerReceiverCapability.metricKitPayloads`).
    @MainActor static var metricKitPayloads: DebugDrawerSidecarPlugin {
        DebugDrawerSidecarPlugin(
            id: MetricKitPayloadsMirror.pluginID, title: "MetricKit", icon: "waveform.path.ecg",
            snapshot: MetricKitPayloadsMirror.Snapshot.self, command: MetricKitPayloadsMirror.Command.self
        ) { transport in
            MetricKitPayloadsPlugin(transport: transport)
        }
    }
}

/// The host's payloads, newest first, each with its JSON to copy.
struct MetricKitPayloadsPlugin: DebugDrawerPlugin {
    let transport: DebugDrawerPluginTransport<MetricKitPayloadsMirror.Snapshot, MetricKitPayloadsMirror.Command>
    let title = "MetricKit"
    let icon = "waveform.path.ecg"

    var body: some View {
        MetricKitPayloadsView(transport: transport)
    }
}

private struct MetricKitPayloadsView: View {
    @ObservedObject var transport: DebugDrawerPluginTransport<MetricKitPayloadsMirror.Snapshot, MetricKitPayloadsMirror.Command>

    var body: some View {
        if transport.snapshot.payloads.isEmpty {
            DebugDrawerEmptyState("No Payloads", systemImage: "waveform.path.ecg") {
                Text("MetricKit hands the app its payloads on a device: a crash diagnostic on the launch after a crash.")
            }
        } else {
            DebugDrawerSection("Payloads") {
                ForEach(transport.snapshot.payloads) { payload in
                    DebugDrawerRow(payload.kind == .diagnostics ? "Diagnostics" : "Metrics") {
                        Text("\(payload.begin.formatted()) – \(payload.end.formatted())")
                    } accessory: {
                        DebugDrawerCopyButton("Copy JSON") { String(bytes: payload.json, encoding: .utf8) }
                    }
                }
            }
            DebugDrawerActionRow {
                EmptyView()
            } trailing: {
                Button("Delete All", role: .destructive) { transport.send(.deleteAll) }
                    .debugDrawerButtonStyle(.destructive)
            }
        }
    }
}
