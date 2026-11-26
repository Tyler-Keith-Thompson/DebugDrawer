// The README's "Resetting the app's state" example, verbatim, so the README cannot drift from the
// code. The app's real state is behind it, so the test resets nothing and reads nothing: it checks
// what the host allowed and that the keychain, which it didn't, is refused, as a sidecar's commands
// are, from the store.
#if DEBUG
    import DebugDrawerAppStateReset
    @testable import DebugDrawerReceiver
    import Foundation
    import Testing

    @MainActor
    private final class ProductionReset {
        let sessions = DebugDrawerSessions(maximumDuration: 15 * 60)
        let receiver: DebugDrawerReceiver

        init(container: URL) throws {
            receiver = DebugDrawerReceiver(directory: container.appending(path: "DebugDrawer"), sessions: sessions)
            try receiver.enable(.appStateReset(AppStateResetRequests(
                sessions: sessions,
                allowing: [.userDefaults, .caches, .urlCache, .cookies],
                launchURL: URL(string: "shop-internal://")
            )))
            try receiver.start()
        }
    }

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct AppStateResetREADMETests {
        @Test("README: the host's categories are served, and a reset of the keychain it didn't allow is refused in the session")
        func readmeAppStateReset() async throws {
            let container = FileManager.default.temporaryDirectory.appending(path: "READMEAppStateReset-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: container) }
            let app = try ProductionReset(container: container)
            defer { app.receiver.stop() }
            app.sessions.perform(.open(duration: 60))
            let layout = AppGroupStoreLayout(directory: app.receiver.appDirectory)
            let confirmation = AppStateResetRequests.Confirmation(category: .keychain, revision: "any")
            let payload = try TransportMessage.payload(AppStateResetRequests.Command.reset([confirmation]))
            let document = StoreDocument(TransportMessage(kind: .command, pluginID: AppStateResetRequests.pluginID, payload: payload))
            try layout.write(document.encoded(), to: layout.commands.appending(path: "0.json"))
            let snapshotFile = layout.snapshotFile(for: AppStateResetRequests.pluginID)
            let watcher = try #require(DirectoryWatcher(directory: layout.snapshots))
            defer { watcher.cancel() }

            app.receiver.reevaluateGates()

            /// The snapshot file's snapshot, once one for the open session is written.
            func served() -> AppStateResetRequests.Snapshot? {
                let payload = (try? Data(contentsOf: snapshotFile)).flatMap(StoreDocument.decoded(from:))?.message.payload
                let snapshot = payload.flatMap { try? JSONDecoder().decode(AppStateResetRequests.Snapshot.self, from: $0) }
                return snapshot?.sessionID == nil ? nil : snapshot
            }
            var snapshot = served()
            if snapshot == nil {
                for await _ in watcher.changes {
                    snapshot = served()
                    if snapshot != nil {
                        break
                    }
                }
            }
            #expect(snapshot?.allowed == [.userDefaults, .caches, .cookies, .urlCache])
            #expect(snapshot?.launchURL == URL(string: "shop-internal://"))
            #expect(snapshot?.listing == nil)
            #expect(app.sessions.auditLog.last?.event == .commandRefused(.notExposed))
        }
    }
#endif
