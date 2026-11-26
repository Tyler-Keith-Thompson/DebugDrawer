// The README's "Auth actions: expired tokens, refreshes and log outs" example, verbatim, so the
// README cannot drift from the code: the app's auth service and its actions, asked for as a
// sidecar's commands are, from the store.
@testable import DebugDrawerReceiver
import Foundation
import Testing

@MainActor
private final class AuthService {
    private var accessToken: String? = "access-token-from-the-server"
    private(set) var state = "Signed in"

    func expireAccessToken() { state = "Expired" }
    func refresh() async -> Bool {
        guard accessToken != nil else { return false }
        accessToken = "a-new-access-token"
        state = "Signed in"
        return true
    }
    func logOut() {
        accessToken = nil
        state = "Signed out"
    }
}

@MainActor
private final class ProductionAuthActions {
    let sessions = DebugDrawerSessions(maximumDuration: 15 * 60)
    let receiver: DebugDrawerReceiver

    init(auth: AuthService, container: URL) throws {
        receiver = DebugDrawerReceiver(directory: container.appending(path: "DebugDrawer"), sessions: sessions)
        try receiver.enable(.authActions([
            .expireAccessToken {
                auth.expireAccessToken()
                return .succeeded
            },
            .forceRefresh {
                await auth.refresh() ? .succeeded : .failed("Not signed in")
            },
            .logOut {
                auth.logOut()
                return .succeeded
            }
        ], launchURL: URL(string: "shop-internal://")))
        try receiver.start()
    }
}

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct AuthActionsREADMETests {
    @Test("README: a log out, then a refresh, left in the store run the app's handlers in a session; the refresh fails signed out")
    func readmeAuthActions() async throws {
        let container = FileManager.default.temporaryDirectory.appending(path: "READMEAuthActions-\(UUID().uuidString)")
        let auth = AuthService()
        let app = try ProductionAuthActions(auth: auth, container: container)
        defer { app.receiver.stop() }
        app.sessions.perform(.open(duration: 60))
        let layout = AppGroupStoreLayout(directory: app.receiver.appDirectory)
        for (index, id) in ["log-out", "force-refresh"].enumerated() {
            let payload = try TransportMessage.payload(DebugDrawerAuthActions.Command.perform(action: id))
            let document = StoreDocument(TransportMessage(kind: .command, pluginID: DebugDrawerAuthActions.pluginID, payload: payload))
            try layout.write(document.encoded(), to: layout.commands.appending(path: "\(index).json"))
        }
        let snapshotFile = layout.snapshotFile(for: DebugDrawerAuthActions.pluginID)
        let watcher = try #require(DirectoryWatcher(directory: layout.snapshots))
        defer { watcher.cancel() }

        app.receiver.reevaluateGates()

        /// The refresh's run in the snapshot file, once it has finished.
        func finishedRefresh() -> DebugDrawerAuthActions.Run? {
            let payload = (try? Data(contentsOf: snapshotFile)).flatMap(StoreDocument.decoded(from:))?.message.payload
            let snapshot = payload.flatMap { try? JSONDecoder().decode(DebugDrawerAuthActions.Snapshot.self, from: $0) }
            return snapshot?.actions.first { $0.id == "force-refresh" }?.lastRun.flatMap { $0.status == .running ? nil : $0 }
        }
        var refresh = finishedRefresh()
        if refresh == nil {
            for await _ in watcher.changes {
                refresh = finishedRefresh()
                if refresh != nil {
                    break
                }
            }
        }
        #expect(auth.state == "Signed out")
        #expect(refresh?.status == .failed(message: "Not signed in"))
    }
}
