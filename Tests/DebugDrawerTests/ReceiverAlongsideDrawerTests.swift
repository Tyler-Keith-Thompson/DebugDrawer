#if DEBUG
    import Combine
    import DebugDrawer
    @testable import DebugDrawerReceiver
    import Foundation
    import Testing

    /// A flag service the test reads back.
    @MainActor
    private final class FakeFlagAdapter: DebugDrawerFeatureFlagAdapter {
        var overrides: [String: DebugDrawerFeatureFlagValue] = [:]

        func overridableFlags() -> [DebugDrawerFeatureFlag] {
            [DebugDrawerFeatureFlag(key: "new-checkout", value: overrides["new-checkout"] ?? .bool(false))]
        }

        func setOverride(_ value: DebugDrawerFeatureFlagValue, forKey key: String) {
            overrides[key] = value
        }

        func clearOverride(forKey key: String) {
            overrides[key] = nil
        }
    }

    // In a debug build the receiver runs beside the drawer: the same capability model the receiver
    // serves a sidecar is shown in the process through the drawer's direct transport, so what a
    // sidecar does to it is seen, and tested, in the app's own drawer.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct ReceiverAlongsideDrawerTests {
        @Test("A sidecar's override through the receiver shows in the drawer's direct transport to the same model")
        func sidecarOverrideShowsInDrawer() async throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: "ReceiverAlongsideDrawerTests-\(UUID().uuidString)")
            let model = DebugDrawerFeatureFlagOverrides(adapter: FakeFlagAdapter())
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
            sut.enable(.featureFlagOverrides(model))
            let drawer = DebugDrawerPluginTransport.direct(to: model)
            try sut.start()
            defer { sut.stop() }
            sessions.perform(.open(duration: 60))
            let (arrivals, arrival) = AsyncStream<DebugDrawerAuditEntry>.makeStream()
            let subscription = sessions.auditEntries.sink { arrival.yield($0) }
            defer { subscription.cancel() }
            let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
            let payload = try TransportMessage.payload(DebugDrawerFeatureFlagOverrides.Command.setOverride(key: "new-checkout", value: .bool(true)))
            let document = StoreDocument(TransportMessage(kind: .command, pluginID: DebugDrawerFeatureFlagOverrides.pluginID, payload: payload))
            let expected = [DebugDrawerFeatureFlag(key: "new-checkout", value: .bool(true))]

            try layout.write(document.encoded(), to: layout.commands.appending(path: "0.json"))
            var entry: DebugDrawerAuditEntry?
            for await recorded in arrivals {
                entry = recorded
                break
            }

            #expect(entry?.event == .commandApplied)
            #expect(drawer.snapshot.flags == expected)
        }
    }
#endif
