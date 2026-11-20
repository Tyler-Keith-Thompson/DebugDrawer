// The README's production MetricKit example, verbatim, so the README cannot drift from the code.
// The default directory is in Application Support, under the home folder the test runners point
// at a temporary one (CFFIXED_USER_HOME).
#if DEBUG
    import DebugDrawer
    import DebugDrawerMetricKit
    import DebugDrawerReceiver
    import Foundation
    import Testing

    @MainActor
    final class ProductionDiagnostics {
        let sessions = DebugDrawerSessions(maximumDuration: 15 * 60)
        let receiver: DebugDrawerReceiver

        init(container: URL) throws {
            receiver = DebugDrawerReceiver(directory: container.appending(path: "DebugDrawer"), sessions: sessions)
            receiver.enable(.metricKitPayloads(sessions: sessions))
            try receiver.start()
        }
    }

    @MainActor
    @Suite("README examples")
    struct READMEExamplesTests {
        @Test(
            "Production builds: crash reports and MetricKit payloads: the capability is served, and empty until a session opens",
            .timeLimit(.minutes(1))
        )
        func productionMetricKit() async throws {
            let container = FileManager.default.temporaryDirectory.appending(path: "READMEMetricKit-\(UUID().uuidString)")
            let diagnostics = try ProductionDiagnostics(container: container)
            defer { diagnostics.receiver.stop() }

            let sidecar = try DebugDrawerAppGroupStoreTransport(directory: container.appending(path: "DebugDrawer"))
            let payloads = try await sidecar.connect(
                toPlugin: MetricKitPayloadsMirror.pluginID,
                snapshot: MetricKitPayloadsMirror.Snapshot.self,
                command: MetricKitPayloadsMirror.Command.self
            )
            #expect(diagnostics.receiver.enabledCapabilities == [MetricKitPayloadsMirror.pluginID])
            #expect(payloads.snapshot == MetricKitPayloadsMirror.Snapshot(sessionID: nil, payloads: []))
        }
    }
#endif
