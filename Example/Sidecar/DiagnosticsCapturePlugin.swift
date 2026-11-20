import DebugDrawer
import DebugDrawerReceiver
import DebugDrawerSidecarKit
import SwiftUI

extension DebugDrawerSidecarPlugin {
    /// What the host logs and sends, captured for the session once started
    /// (`DebugDrawerReceiverCapability.diagnosticsCapture`).
    @MainActor static var diagnosticsCapture: DebugDrawerSidecarPlugin {
        DebugDrawerSidecarPlugin(
            id: DebugDrawerDiagnosticsCapture.pluginID, title: "Diagnostics", icon: "stethoscope",
            snapshot: DebugDrawerDiagnosticsCapture.Snapshot.self, command: DebugDrawerDiagnosticsCapture.Command.self
        ) { transport in
            DiagnosticsCapturePlugin(transport: transport)
        }
    }
}

/// The host's captured log lines and requests, redacted in the host, with Start Capture and Stop
/// and Delete; Create Report copies them into the report and tells the host it exported them.
struct DiagnosticsCapturePlugin: DebugDrawerPlugin, DebugDrawerReportContributor {
    let transport: DebugDrawerPluginTransport<DebugDrawerDiagnosticsCapture.Snapshot, DebugDrawerDiagnosticsCapture.Command>
    let title = "Diagnostics"
    let icon = "stethoscope"

    var body: some View {
        DiagnosticsCaptureView(transport: transport)
    }

    /// Adds `console.log` and `network.json`, what the host captured, already redacted there, then
    /// tells the host, which records the export and audits it. The host's copy is still deleted as
    /// the session ends; the report's is the one that stays.
    func contribute(to report: inout DebugDrawerReport, redaction: DebugDrawerRedaction) {
        let snapshot = transport.snapshot
        guard snapshot.isCapturing, !snapshot.lines.isEmpty || !snapshot.requests.isEmpty else { return }
        report.add(text: snapshot.consoleLog, named: "console")
        report.add(jsonData: snapshot.networkJSON, named: "network")
        transport.send(.export)
    }
}

private struct DiagnosticsCaptureView: View {
    @ObservedObject var transport: DebugDrawerPluginTransport<DebugDrawerDiagnosticsCapture.Snapshot, DebugDrawerDiagnosticsCapture.Command>

    var body: some View {
        let snapshot = transport.snapshot
        if snapshot.isCapturing {
            DebugDrawerSection("Console") {
                ForEach(snapshot.lines.reversed()) { line in
                    DebugDrawerRow(line.message) {
                        Text([line.level.rawValue, line.subsystem, line.category].filter { !$0.isEmpty }.joined(separator: " · "))
                    } accessory: {
                        Text(line.timestamp, style: .time)
                            .debugDrawerFont(.value)
                    }
                }
            } footer: {
                Text("\(snapshot.byteCount.formatted(.byteCount(style: .file))) kept, \(snapshot.dropped) dropped by the bounds")
            }
            DebugDrawerSection("Network") {
                ForEach(snapshot.requests.reversed()) { request in
                    DebugDrawerRow("\(request.method) \(request.url)") {
                        Text(request.statusCode.map(String.init) ?? request.failure ?? "No response")
                    }
                }
            }
            DebugDrawerActionRow {
                EmptyView()
            } trailing: {
                Button("Stop and Delete", role: .destructive) { transport.send(.stop) }
                    .debugDrawerButtonStyle(.destructive)
            }
        } else {
            DebugDrawerEmptyState("Not Capturing", systemImage: "stethoscope") {
                Text("Start captures what the app logs and sends, redacted, until the session ends, when the app deletes it.")
            }
            DebugDrawerActionRow {
                Button("Start Capture") { transport.send(.start) }
            }
        }
    }
}
