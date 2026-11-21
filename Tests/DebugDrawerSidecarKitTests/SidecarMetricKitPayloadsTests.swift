// MetricKit's capability module isn't built for watchOS, so neither is the kit's plugin for it.
#if DEBUG && os(macOS)
    import DebugDrawer
    import DebugDrawerMetricKit
    @testable import DebugDrawerSidecarKit
    import Foundation
    import Testing
    import ViewInspector

    // The MetricKit plugin as a function of the capability's snapshot, and its part of the
    // sidecar's report, over a transport holding a fixed snapshot.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct SidecarMetricKitPayloadsTests {
        private let crash = MetricKitPayloadsMirror.Payload(
            id: UUID(), kind: .diagnostics,
            begin: Date(timeIntervalSince1970: 1_800_000_000), end: Date(timeIntervalSince1970: 1_800_086_400),
            received: Date(timeIntervalSince1970: 1_800_090_000), json: Data(#"{"crashDiagnostics":[]}"#.utf8)
        )

        @Test("Each payload is listed by kind with Delete, which sends its ID; Delete All sends deleteAll")
        func viewSendsDeletes() throws {
            var sent: [MetricKitPayloadsMirror.Command] = []
            let sut = MetricKitPayloadsView(snapshot: MetricKitPayloadsMirror.Snapshot(sessionID: UUID(), payloads: [crash])) { sent.append($0) }

            try sut.inspect().find(viewWithAccessibilityIdentifier: "MetricKitPayload-\(crash.id.uuidString)").find(button: "Delete").tap()
            try sut.inspect().find(button: "Delete All").tap()

            #expect(sent == [.delete(id: crash.id), .deleteAll])
            #expect(throws: Never.self) { try sut.inspect().find(text: "Diagnostics") }
        }

        @Test("With no payload the plugin says why: no session, or none from MetricKit yet")
        func emptyStates() throws {
            let noSession = MetricKitPayloadsView(snapshot: MetricKitPayloadsMirror.Snapshot(sessionID: nil, payloads: [])) { _ in }
            let none = MetricKitPayloadsView(snapshot: MetricKitPayloadsMirror.Snapshot(sessionID: UUID(), payloads: [])) { _ in }

            #expect(throws: Never.self) { try noSession.inspect().find(text: "The app shows the payloads it keeps only while a session is open.") }
            #expect(throws: Never.self) {
                try none.inspect().find(text: "MetricKit hands the app its payloads on a device: a crash diagnostic on the launch after a crash.")
            }
            #expect(throws: (any Error).self) { try none.inspect().find(button: "Delete All") }
        }

        @Test("Create Report adds each payload's JSON, named for its kind and the end of its period")
        func reportContribution() throws {
            let transport = DebugDrawerPluginTransport<MetricKitPayloadsMirror.Snapshot, MetricKitPayloadsMirror.Command>(
                initial: MetricKitPayloadsMirror.Snapshot(sessionID: UUID(), payloads: [crash]), snapshots: AsyncStream { $0.finish() }
            ) { _ in }
            let sut = MetricKitPayloadsSidecarPlugin(transport: transport)
            var report = DebugDrawerReport()

            sut.contribute(to: &report, redaction: DebugDrawerRedaction())

            let file = try #require(report.files.first)
            #expect(file.name == "diagnostics-2027-01-16T080000Z.json")
            #expect(file.data == crash.json)
        }

        @Test("The shipped MetricKit plugin is served under the capability's ID")
        func shippedPlugin() {
            let sut = DebugDrawerSidecarPlugin.metricKitPayloads

            #expect([sut.id, sut.title, sut.icon] == [MetricKitPayloadsMirror.pluginID, "MetricKit", "waveform.path.ecg"])
        }
    }
#endif
