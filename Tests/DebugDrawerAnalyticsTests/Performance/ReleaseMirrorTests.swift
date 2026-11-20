// The release build. `--config=release` builds and runs only the performance targets, so this is
// where the mirror is tested compiled without DEBUG, as a production app's build is: through the
// public API alone, a real receiver, and the snapshot file it leaves in the store, which a sidecar
// reads. In debug the file is empty; AnalyticsMirrorSessionTests and AnalyticsMirrorRedactionTests
// cover the same through the sidecar's transport.
#if !DEBUG
    import DebugDrawerAnalytics
    import DebugDrawerReceiver
    import Foundation
    import Testing

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct ReleaseMirrorTests {
        @Test("In release, record evaluates nothing while no session is open, and mirrors redacted events to the store while one is")
        func mirrorsInRelease() async throws {
            let prefix = "release-\(UUID().uuidString)-"
            let directory = FileManager.default.temporaryDirectory.appending(path: "ReleaseMirrorTests-\(UUID().uuidString)")
            let layout = AppGroupStoreLayout(directory: directory)
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let receiver = DebugDrawerReceiver(directory: directory, sessions: sessions)
            receiver.enable(.analyticsEvents(sessions: sessions))
            try receiver.start()
            defer { receiver.stop() }
            let watcher = try #require(DirectoryWatcher(directory: layout.snapshots))
            defer { watcher.cancel() }
            let file = layout.snapshotFile(for: AnalyticsEventsMirror.pluginID)
            var evaluations = 0
            func name() -> String {
                evaluations += 1
                return "\(prefix)before"
            }
            func read() -> AnalyticsEventsMirror.Snapshot? {
                guard let data = try? Data(contentsOf: file), let document = StoreDocument.decoded(from: data) else { return nil }
                return try? JSONDecoder().decode(AnalyticsEventsMirror.Snapshot.self, from: document.message.payload)
            }
            let password = "release-dd124-secret"

            AnalyticsEvents.record(name())
            sessions.perform(.open(duration: 60))
            AnalyticsEvents.record("\(prefix)during", properties: ["password": .string(password), "plan": "pro"])
            var snapshot = read()
            if snapshot?.events.contains(where: { $0.name.hasPrefix(prefix) }) != true {
                for await _ in watcher.changes {
                    snapshot = read()
                    if snapshot?.events.contains(where: { $0.name.hasPrefix(prefix) }) == true { break }
                }
            }
            let ours = snapshot?.events.filter { $0.name.hasPrefix(prefix) }
            let bytes = try Data(contentsOf: file)

            #expect(evaluations == 0)
            #expect(ours?.map(\.name) == ["\(prefix)during"])
            #expect(ours?.first?.properties == ["password": .string(AnalyticsRedaction.mask), "plan": "pro"])
            #expect(bytes.range(of: Data(password.utf8)) == nil)
        }
    }
#endif
