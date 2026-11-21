#if DEBUG && os(macOS)
    import DebugDrawer
    @testable import DebugDrawerReceiver
    @testable import DebugDrawerSidecarKit
    import Foundation
    import Testing
    import ViewInspector

    // The Diagnostics plugin as a function of the capability's snapshot, and its part of the
    // sidecar's report, over a transport holding a fixed snapshot.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct SidecarDiagnosticsCaptureTests {
        private let started = Date(timeIntervalSince1970: 1_800_000_000)

        private var capturing: DebugDrawerDiagnosticsCapture.Snapshot {
            DebugDrawerDiagnosticsCapture.Snapshot(
                sessionID: UUID(),
                lines: [
                    .init(
                        id: 1, timestamp: started, level: .notice, message: "Signed in as [REDACTED]",
                        metadata: [:], subsystem: "com.example", category: "auth"
                    )
                ],
                requests: [
                    .init(
                        id: 2, started: started, finished: started, method: "GET", url: "https://api.example.com/greeting",
                        requestHeaders: [:], requestBody: nil, statusCode: 200, responseHeaders: [:], responseBody: nil, failure: nil
                    )
                ],
                dropped: 0, byteCount: 120, limits: .standard, exports: []
            )
        }

        @Test("While not capturing the plugin offers Start Capture, which sends start")
        func startCapture() throws {
            let snapshot = DebugDrawerDiagnosticsCapture.Snapshot(
                sessionID: nil, lines: [], requests: [], dropped: 0, byteCount: 0, limits: .standard, exports: []
            )
            var sent: [DebugDrawerDiagnosticsCapture.Command] = []
            let sut = DiagnosticsCaptureView(snapshot: snapshot) { sent.append($0) }

            try sut.inspect().find(button: "Start Capture").tap()

            #expect(sent == [.start])
            #expect(throws: Never.self) { try sut.inspect().find(text: "Not Capturing") }
            #expect(throws: (any Error).self) { try sut.inspect().find(button: "Stop and Delete") }
        }

        @Test("While capturing the plugin shows each line and request as the app redacted it, and Stop and Delete sends stop")
        func capturingShowsEntries() throws {
            var sent: [DebugDrawerDiagnosticsCapture.Command] = []
            let sut = DiagnosticsCaptureView(snapshot: capturing) { sent.append($0) }

            try sut.inspect().find(button: "Stop and Delete").tap()

            #expect(sent == [.stop])
            #expect(throws: Never.self) { try sut.inspect().find(text: "Signed in as [REDACTED]") }
            #expect(throws: Never.self) { try sut.inspect().find(text: "GET https://api.example.com/greeting") }
            #expect(throws: Never.self) { try sut.inspect().find(text: "200") }
            #expect(throws: (any Error).self) { try sut.inspect().find(button: "Start Capture") }
        }

        @Test("Create Report adds console.txt and network.json from the snapshot and tells the app it was exported")
        func reportContribution() throws {
            var sent: [DebugDrawerDiagnosticsCapture.Command] = []
            let transport = DebugDrawerPluginTransport<DebugDrawerDiagnosticsCapture.Snapshot, DebugDrawerDiagnosticsCapture.Command>(
                initial: capturing, snapshots: AsyncStream { $0.finish() }
            ) { sent.append($0) }
            let sut = DiagnosticsCaptureSidecarPlugin(transport: transport)
            var report = DebugDrawerReport()

            sut.contribute(to: &report, redaction: DebugDrawerRedaction())

            let console = try #require(report.files.first { $0.name == "console.txt" })
            #expect(String(data: console.data, encoding: .utf8)?.contains("Signed in as [REDACTED]") == true)
            #expect(report.files.contains { $0.name == "network.json" })
            #expect(sent == [.export])
        }

        @Test("Create Report adds nothing and exports nothing while the app captures nothing")
        func noContributionWhenEmpty() {
            var sent: [DebugDrawerDiagnosticsCapture.Command] = []
            let empty = DebugDrawerDiagnosticsCapture.Snapshot(
                sessionID: UUID(), lines: [], requests: [], dropped: 0, byteCount: 0, limits: .standard, exports: []
            )
            let transport = DebugDrawerPluginTransport<DebugDrawerDiagnosticsCapture.Snapshot, DebugDrawerDiagnosticsCapture.Command>(
                initial: empty, snapshots: AsyncStream { $0.finish() }
            ) { sent.append($0) }
            let sut = DiagnosticsCaptureSidecarPlugin(transport: transport)
            var report = DebugDrawerReport()

            sut.contribute(to: &report, redaction: DebugDrawerRedaction())

            #expect(report.files.isEmpty)
            #expect(sent.isEmpty)
        }

        @Test("The shipped Diagnostics plugin is served under the capability's ID")
        func shippedPlugin() {
            let sut = DebugDrawerSidecarPlugin.diagnosticsCapture

            #expect([sut.id, sut.title, sut.icon] == [DebugDrawerDiagnosticsCapture.pluginID, "Diagnostics", "stethoscope"])
        }
    }
#endif
