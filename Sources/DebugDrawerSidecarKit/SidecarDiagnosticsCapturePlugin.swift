import DebugDrawer
import Foundation
import SwiftUI

// The sidecar's half of the diagnostics capture (DD-112): Start Capture, then the log lines and
// requests the app hands its capture (`DebugDrawerDiagnosticsCapture`, in the receiver), newest
// first and already redacted there, with Stop and Delete. It ships in the kit, beside Performance,
// as the capture describes itself, so every sidecar would draw the same lists. Capture starts from
// a button, not as the plugin shows, as the app keeps nothing until a sidecar asks. It is a
// `DebugDrawerReportContributor`, so Create Report adds `console.txt` and `network.json` and tells
// the app it was exported.

#if DEBUG
    extension DebugDrawerSidecarPlugin {
        /// What the app logs and sends (`DebugDrawerReceiverCapability.diagnosticsCapture(_:)`),
        /// captured once Start Capture is pressed and redacted in the app, until Stop and Delete or
        /// the session's end; Create Report adds it as `console.txt` and `network.json`.
        @MainActor public static var diagnosticsCapture: DebugDrawerSidecarPlugin {
            DebugDrawerSidecarPlugin(
                id: DebugDrawerDiagnosticsCapture.pluginID, title: "Diagnostics", icon: "stethoscope",
                snapshot: DebugDrawerDiagnosticsCapture.Snapshot.self, command: DebugDrawerDiagnosticsCapture.Command.self
            ) { transport in
                DiagnosticsCaptureSidecarPlugin(transport: transport)
            }
        }
    }

    /// The app's captured log lines and requests, shown in the sidecar.
    struct DiagnosticsCaptureSidecarPlugin: DebugDrawerPlugin, DebugDrawerReportContributor {
        let transport: DebugDrawerPluginTransport<DebugDrawerDiagnosticsCapture.Snapshot, DebugDrawerDiagnosticsCapture.Command>
        let title = "Diagnostics"
        let icon = "stethoscope"

        var body: some View {
            DiagnosticsCaptureTransportView(transport: transport)
        }

        /// Adds `console.txt` and `network.json`, what the app captured, already redacted there,
        /// then tells the app, which records the export and audits it. The app's copy is still
        /// deleted as the session ends; the report's is the one that stays.
        func contribute(to report: inout DebugDrawerReport, redaction _: DebugDrawerRedaction) {
            let snapshot = transport.snapshot
            guard snapshot.isCapturing, !snapshot.lines.isEmpty || !snapshot.requests.isEmpty else { return }
            report.add(text: snapshot.consoleLog, named: "console")
            report.add(jsonData: snapshot.networkJSON, named: "network")
            transport.send(.export)
        }
    }

    /// The capture over the capability's snapshot, sending what the view asks.
    struct DiagnosticsCaptureTransportView: View {
        @ObservedObject var transport: DebugDrawerPluginTransport<DebugDrawerDiagnosticsCapture.Snapshot, DebugDrawerDiagnosticsCapture.Command>

        var body: some View {
            DiagnosticsCaptureView(snapshot: transport.snapshot) { transport.send($0) }
        }
    }

    /// Start Capture while nothing is captured; then the lines and requests, newest first, and
    /// Stop and Delete. A function of the snapshot and the send action.
    struct DiagnosticsCaptureView: View {
        let snapshot: DebugDrawerDiagnosticsCapture.Snapshot
        let send: (DebugDrawerDiagnosticsCapture.Command) -> Void

        var body: some View {
            if snapshot.isCapturing {
                DebugDrawerSection("Console") {
                    if snapshot.lines.isEmpty {
                        Text("No line yet: the app's logger hands its lines to the capture as it writes them.")
                            .debugDrawerFont(.label)
                            .foregroundStyle(.secondary)
                            .debugDrawerRowPadding()
                    }
                    ForEach(snapshot.lines.reversed()) { line in
                        DebugDrawerRow(line.message) {
                            Text([line.level.rawValue, line.subsystem, line.category].filter { !$0.isEmpty }.joined(separator: " · "))
                        } accessory: {
                            Text(line.timestamp, style: .time)
                                .debugDrawerFont(.value)
                        }
                        .accessibilityElement(children: .combine)
                    }
                } footer: {
                    Text("\(snapshot.byteCount.formatted(.byteCount(style: .file))) kept, \(snapshot.dropped) dropped by the bounds")
                }
                DebugDrawerSection("Network") {
                    if snapshot.requests.isEmpty {
                        Text("No request yet: the app records each request it sends once it has its outcome.")
                            .debugDrawerFont(.label)
                            .foregroundStyle(.secondary)
                            .debugDrawerRowPadding()
                    }
                    ForEach(snapshot.requests.reversed()) { request in
                        DebugDrawerRow("\(request.method) \(request.url)") {
                            Text(request.statusCode.map { "\($0)" } ?? request.failure ?? "No response")
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                DebugDrawerActionRow {
                    EmptyView()
                } trailing: {
                    Button("Stop and Delete", role: .destructive) { send(.stop) }
                        .debugDrawerButtonStyle(.destructive)
                        .accessibilityLabel("Stop and Delete")
                        .accessibilityHint("Stops capturing and deletes what the app captured")
                }
            } else {
                DebugDrawerEmptyState("Not Capturing", systemImage: "stethoscope") {
                    Text(
                        "Start Capture keeps what the app logs and sends, redacted in the app, until the session ends, when the app deletes it."
                    )
                }
                DebugDrawerActionRow {
                    Button("Start Capture") { send(.start) }
                        .debugDrawerButtonStyle(.primary)
                        .accessibilityLabel("Start Capture")
                }
            }
        }
    }
#else
    // The release stand-in: the same member, over a plugin that draws nothing; a release build's
    // transports connect to nothing anyway.

    extension DebugDrawerSidecarPlugin {
        /// What the app logs and sends; release builds show nothing.
        @MainActor public static var diagnosticsCapture: DebugDrawerSidecarPlugin {
            DebugDrawerSidecarPlugin(
                id: DebugDrawerDiagnosticsCapture.pluginID, title: "Diagnostics", icon: "stethoscope",
                snapshot: DebugDrawerDiagnosticsCapture.Snapshot.self, command: DebugDrawerDiagnosticsCapture.Command.self
            ) { _ in
                DiagnosticsCaptureSidecarPlugin()
            }
        }
    }

    /// Draws nothing.
    struct DiagnosticsCaptureSidecarPlugin: DebugDrawerPlugin {
        let title = "Diagnostics"
        let icon = "stethoscope"

        var body: some View {
            EmptyView()
        }
    }
#endif
