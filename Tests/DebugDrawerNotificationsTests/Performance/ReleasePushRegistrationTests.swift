// The release build. `--config=release` builds and runs only the performance targets, so this is
// where the capability is tested compiled without DEBUG, as a production app's build is: a real
// receiver, the mirror's package initializer handed settings of the test's own (a test runner has
// no notification center), and the snapshot file the receiver leaves in the store, which a sidecar
// reads. In debug the file is empty; PushRegistrationSidecarTests covers the same through the
// sidecar's transport.
#if !DEBUG
    import DebugDrawerNotifications
    import DebugDrawerReceiver
    import Foundation
    import Testing

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct ReleasePushRegistrationTests {
        @Test("In release, the store's snapshot holds the token, environment and authorization during a session only")
        func servedDuringSession() async throws {
            let root = FileManager.default.temporaryDirectory.appending(path: "ReleasePushRegistrationTests-\(UUID().uuidString)")
            let store = root.appending(path: "Group/DebugDrawer")
            let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: store))
            let file = layout.snapshotFile(for: PushRegistrationMirror.pluginID)
            func read() -> PushRegistrationMirror.Snapshot? {
                guard let data = try? Data(contentsOf: file), let document = StoreDocument.decoded(from: data) else { return nil }
                return try? JSONDecoder().decode(PushRegistrationMirror.Snapshot.self, from: document.message.payload)
            }
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let receiver = DebugDrawerReceiver(directory: store, sessions: sessions)
            let environment = PushEnvironment(server: .production, source: .appStoreDistribution)
            let mirror = PushRegistrationMirror(
                sessions: sessions, environment: environment, settings: { NotificationSettings(authorization: .authorized, items: []) }
            )
            mirror.didRegisterForRemoteNotifications(withDeviceToken: Data([0x0B, 0xAD, 0xF0, 0x0D]))
            receiver.enable(.pushRegistration(mirror))
            try receiver.start()
            defer { receiver.stop() }
            let watcher = try #require(DirectoryWatcher(directory: layout.snapshots))
            defer { watcher.cancel() }

            sessions.perform(.open(duration: 60))
            var during = read()
            if during?.settings == nil {
                for await _ in watcher.changes {
                    during = read()
                    if during?.settings != nil { break }
                }
            }
            sessions.end()
            var after = read()
            if after?.sessionID != nil {
                for await _ in watcher.changes {
                    after = read()
                    if after?.sessionID == nil { break }
                }
            }

            #expect(during?.registration == .registered(deviceToken: "0badf00d"))
            #expect(during?.environment == environment)
            #expect(during?.settings?.authorization == .authorized)
            #expect(after == PushRegistrationMirror.Snapshot(sessionID: nil, registration: nil, environment: nil, settings: nil))
        }
    }
#endif
