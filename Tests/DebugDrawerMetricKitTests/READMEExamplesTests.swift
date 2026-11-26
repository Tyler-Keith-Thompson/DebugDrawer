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
            try receiver.enable(.metricKitPayloads(sessions: sessions))
            try receiver.start()
        }
    }

    @MainActor
    @Suite("README examples")
    struct READMEExamplesTests {
        @Test(
            "Production builds: crash reports and MetricKit payloads: enabled, and nothing of it is in the store until a session opens",
            .timeLimit(.minutes(1))
        )
        func productionMetricKit() async throws {
            let container = FileManager.default.temporaryDirectory.appending(path: "READMEMetricKit-\(UUID().uuidString)")
            let diagnostics = try ProductionDiagnostics(container: container)
            defer { diagnostics.receiver.stop() }

            let appDirectory = AppGroupStoreLayout.appDirectory(inStore: container.appending(path: "DebugDrawer"))
            let snapshotFile = AppGroupStoreLayout(directory: appDirectory).snapshotFile(for: MetricKitPayloadsMirror.pluginID)

            #expect(diagnostics.receiver.enabledCapabilities == [MetricKitPayloadsMirror.pluginID])
            #expect(!FileManager.default.fileExists(atPath: snapshotFile.path))
        }
    }
#endif
