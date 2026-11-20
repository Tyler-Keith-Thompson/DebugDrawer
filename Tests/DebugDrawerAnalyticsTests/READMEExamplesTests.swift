// The README's production analytics example, verbatim, so the README cannot drift from the code.
#if DEBUG
    import DebugDrawer
    import DebugDrawerAnalytics
    import DebugDrawerReceiver
    import Foundation
    import Testing

    @MainActor
    final class ProductionAnalyticsMirror {
        let sessions = DebugDrawerSessions(maximumDuration: 15 * 60)
        let receiver: DebugDrawerReceiver

        init(container: URL) throws {
            receiver = DebugDrawerReceiver(directory: container.appending(path: "DebugDrawer"), sessions: sessions)
            receiver.enable(.analyticsEvents(
                sessions: sessions,
                redaction: .standard.adding(keys: ["customer_name"], values: [#"\bACCT-\d{6}\b"#])
            ))
            try receiver.start()
        }
    }

    @MainActor
    @Suite("README examples")
    struct READMEExamplesTests {
        @Test("Production builds: analytics events: the mirror is served, and empty until a session opens", .timeLimit(.minutes(1)))
        func productionAnalytics() async throws {
            let container = FileManager.default.temporaryDirectory.appending(path: "READMEAnalytics-\(UUID().uuidString)")
            let mirror = try ProductionAnalyticsMirror(container: container)
            defer { mirror.receiver.stop() }

            // Wherever the app sends an event, in every build:
            AnalyticsEvents.record("checkout_completed", properties: ["plan": "pro", "seats": 3], source: "Segment")

            let appDirectory = AppGroupStoreLayout.appDirectory(inStore: container.appending(path: "DebugDrawer"))

            let sidecar = try DebugDrawerAppGroupStoreTransport(directory: appDirectory)
            let events = try await sidecar.connect(
                toPlugin: AnalyticsEventsMirror.pluginID, snapshot: AnalyticsEventsMirror.Snapshot.self, command: AnalyticsEventsMirror.Command.self
            )
            #expect(mirror.receiver.enabledCapabilities == [AnalyticsEventsMirror.pluginID])
            #expect(events.snapshot == AnalyticsEventsMirror.Snapshot(sessionID: nil, events: []))
        }
    }
#endif
