// The release build. `--config=release` builds and runs only the performance targets, so this is
// where the capability is tested compiled without DEBUG, as a production app's build is: a real
// receiver, the mirror's package initializer handed a source that delivers the recorded-shape
// crash payload (MetricKit delivers nothing in a test runner), and the snapshot file the receiver
// leaves in the store, which a sidecar reads. In debug the file is empty; MetricKitSidecarTests
// and MetricKitCrashRelaunchExitTests cover the same through the sidecar's transport.
#if !DEBUG
    import DebugDrawerMetricKit
    import DebugDrawerReceiver
    import DebugDrawerTestSupport
    import Foundation
    import Testing

    /// Hands over `held` as it is subscribed, as MetricKit does with its past payloads.
    @MainActor
    private final class HeldPayloadsSource: MetricKitPayloadSource {
        let held: [ReceivedMetricKitPayload]

        init(held: [ReceivedMetricKitPayload]) {
            self.held = held
        }

        func subscribe(_ receive: @escaping @MainActor ([ReceivedMetricKitPayload]) -> Void) {
            receive(held)
        }

        func unsubscribe() {}
    }

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct ReleaseMetricKitTests {
        @Test("In release, a crash payload delivered at one launch is kept, redacted, and served to the store at the next launch's session")
        func crashServedAfterRelaunch() async throws {
            let root = FileManager.default.temporaryDirectory.appending(path: "ReleaseMetricKitTests-\(UUID().uuidString)")
            let store = root.appending(path: "Group/DebugDrawer")
            let archive = root.appending(path: "Payloads")
            let layout = AppGroupStoreLayout(directory: store)
            let file = layout.snapshotFile(for: MetricKitPayloadsMirror.pluginID)
            func read() -> MetricKitPayloadsMirror.Snapshot? {
                guard let data = try? Data(contentsOf: file), let document = StoreDocument.decoded(from: data) else { return nil }
                return try? JSONDecoder().decode(MetricKitPayloadsMirror.Snapshot.self, from: document.message.payload)
            }
            do {
                let sessions = DebugDrawerSessions(maximumDuration: 300)
                let receiver = DebugDrawerReceiver(directory: store, sessions: sessions)
                let source = HeldPayloadsSource(held: [ReceivedMetricKitPayload(kind: .diagnostics, json: MetricKitFixtures.crashDiagnosticPayload)])
                let mirror = MetricKitPayloadsMirror(sessions: sessions, directory: archive, redaction: .standard, capacity: 10, source: source)
                receiver.enable(.model(mirror, id: MetricKitPayloadsMirror.pluginID, scope: .persistent))
                try receiver.start()
                receiver.stop()
            }
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let receiver = DebugDrawerReceiver(directory: store, sessions: sessions)
            let relaunched = MetricKitPayloadsMirror(
                sessions: sessions, directory: archive, redaction: .standard, capacity: 10, source: HeldPayloadsSource(held: [])
            )
            receiver.enable(.model(relaunched, id: MetricKitPayloadsMirror.pluginID, scope: .persistent))
            try receiver.start()
            defer { receiver.stop() }
            let watcher = try #require(DirectoryWatcher(directory: layout.snapshots))
            defer { watcher.cancel() }

            sessions.perform(.open(duration: 60))
            var snapshot = read()
            if snapshot?.payloads.isEmpty != false {
                for await _ in watcher.changes {
                    snapshot = read()
                    if snapshot?.payloads.isEmpty == false { break }
                }
            }

            let served = try #require(snapshot?.payloads)
            #expect(served.map(\.kind) == [.diagnostics])
            let json = try #require(served.first?.json)
            #expect(json.range(of: Data(#""signal":11"#.utf8)) != nil)
            #expect(json.range(of: Data(MetricKitFixtures.crashCustomerEmail.utf8)) == nil)
            #expect(json.range(of: Data(MetricKitRedaction.mask.utf8)) != nil)
        }
    }
#endif
