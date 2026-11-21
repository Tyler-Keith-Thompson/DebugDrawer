// The release build. `--config=release` builds and runs only the performance targets, so this is
// where the capability is tested compiled without DEBUG, as a production app's build is: a real
// receiver, and the snapshot file it leaves in the store, which a sidecar reads. In debug the file
// is empty; AppStateSidecarTests covers the same through the sidecar's transport.
#if !DEBUG
    import DebugDrawerAppInfo
    import DebugDrawerReceiver
    import DebugDrawerTestSupport
    import Foundation
    import Testing

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct ReleaseAppStateTests {
        @Test("In release, the store's snapshot holds the state, the user ID hashed, during a session only")
        func servedDuringSession() async throws {
            let suite = temporarySuiteName("ReleaseAppStateTests")
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let root = FileManager.default.temporaryDirectory.appending(path: "ReleaseAppStateTests-\(UUID().uuidString)")
            let store = root.appending(path: "Group/DebugDrawer")
            let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: store))
            let file = layout.snapshotFile(for: DebugDrawerAppState.pluginID)
            func read() -> DebugDrawerAppState.Snapshot? {
                guard let data = try? Data(contentsOf: file), let document = StoreDocument.decoded(from: data) else { return nil }
                return try? JSONDecoder().decode(DebugDrawerAppState.Snapshot.self, from: document.message.payload)
            }
            let rawID = "release-user-5512"
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let receiver = DebugDrawerReceiver(directory: store, sessions: sessions)
            let appState = DebugDrawerAppState(
                sessions: sessions, buildMetadata: AppInfoBuildMetadata(gitCommit: "4f9c2e1"), userID: { rawID },
                values: [DebugDrawerAppStateField("plan") { "pro" }], defaults: defaults
            )
            receiver.enable(.appState(appState))
            try receiver.start()
            defer { receiver.stop() }
            let watcher = try #require(DirectoryWatcher(directory: layout.snapshots))
            defer { watcher.cancel() }
            let expectedValues: [String: DebugDrawerAppStateValue] = ["plan": "pro"]

            sessions.perform(.open(duration: 60))
            var during = read()
            if during?.state == nil {
                for await _ in watcher.changes {
                    during = read()
                    if during?.state != nil { break }
                }
            }
            let fileDuring = try Data(contentsOf: file)
            let payloadDuring = try #require(StoreDocument.decoded(from: fileDuring)?.message.payload)
            sessions.end()
            // The receiver removes the snapshot as the session ends.
            let after = read()

            #expect(during?.state?.buildMetadata.gitCommit == "4f9c2e1")
            #expect(during?.state?.values == expectedValues)
            #expect(during?.state?.hashedUserID?.count == 64)
            #expect(fileDuring.range(of: Data(rawID.utf8)) == nil)
            #expect(fileDuring.range(of: Data(Data(rawID.utf8).base64EncodedString().utf8)) == nil)
            #expect(payloadDuring.range(of: Data(rawID.utf8)) == nil)
            #expect(after == nil)
            #expect(!FileManager.default.fileExists(atPath: file.path))
        }
    }
#endif
