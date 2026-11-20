// The README's "Switching environments in production" example, verbatim, so the README cannot
// drift from the code: the app's backend switch, its environments enabled under a grant policy, a
// switch left in the store by a sidecar whose grant lists the capability, the indicator, and the
// default back as the session ends.
import CryptoKit
@testable import DebugDrawerReceiver
import Foundation
import SwiftUI
import Testing

@MainActor
private final class BackendSwitcher: DebugDrawerEnvironmentAdapter {
    private(set) var baseURL = "https://api.example.com"

    func activate(_ environment: DebugDrawerEnvironment) {
        switch environment.id {
        case "staging": baseURL = "https://staging.api.example.com"
        case "canary": baseURL = "https://canary.api.example.com"
        default: baseURL = "https://api.example.com"
        }
    }
}

@MainActor
private final class ProductionEnvironments {
    let sessions: DebugDrawerSessions
    let environments: DebugDrawerEnvironments
    let receiver: DebugDrawerReceiver

    init(grantServerKey: Curve25519.Signing.PublicKey, backend: BackendSwitcher, container: URL) throws {
        sessions = DebugDrawerSessions(maximumDuration: 15 * 60, grantPolicy: DebugDrawerGrantPolicy(
            verifier: DebugDrawerSignedGrantVerifier(keys: [.ed25519(grantServerKey)]),
            audience: "com.example.MyApp"
        ))
        environments = DebugDrawerEnvironments(
            default: DebugDrawerEnvironment("production", title: "Production"),
            allowing: DebugDrawerEnvironment("staging", title: "Staging", summary: "Yesterday's server build"),
            DebugDrawerEnvironment("canary", title: "Canary"),
            adapter: backend
        )
        receiver = DebugDrawerReceiver(directory: container.appending(path: "DebugDrawer"), sessions: sessions)
        receiver.enable(.environments(environments))
        try receiver.start()
    }
}

private struct EnvironmentIndicator: View {
    @ObservedObject var environments: DebugDrawerEnvironments

    var body: some View {
        let snapshot = environments.snapshot
        if snapshot.isSwitched, let active = snapshot.environments.first(where: { $0.id == snapshot.activeEnvironment }) {
            Label("Backend: \(active.title)", systemImage: "server.rack")
        }
    }
}

// Run serialized: the README's model keeps its record in the standard defaults, as an app's does.
@MainActor
@Suite(.timeLimit(.minutes(1)), .serialized)
struct EnvironmentsREADMETests {
    @Test("README: a switch to staging in a session whose grant lists it points the app there, shown by the indicator, until the session ends")
    func readmeEnvironments() throws {
        let container = FileManager.default.temporaryDirectory.appending(path: "READMEEnvironments-\(UUID().uuidString)")
        let serverKey = Curve25519.Signing.PrivateKey()
        let backend = BackendSwitcher()
        let app = try ProductionEnvironments(grantServerKey: serverKey.publicKey, backend: backend, container: container)
        defer {
            app.receiver.stop()
            UserDefaults.standard.removeObject(forKey: DebugDrawerEnvironments.activeEnvironmentDefaultsKey)
        }
        let grant = try DebugDrawerTestGrantSigner(key: serverKey).token(for: DebugDrawerGrant(
            id: "g-\(UUID().uuidString)", subject: "jane@example.com", audiences: ["com.example.MyApp"],
            capabilities: [DebugDrawerEnvironments.pluginID], notBefore: Date().addingTimeInterval(-60), expires: Date().addingTimeInterval(600)
        ))
        app.sessions.perform(.open(duration: 300, grant: grant))
        let layout = AppGroupStoreLayout(directory: app.receiver.appDirectory)
        let payload = try TransportMessage.payload(DebugDrawerEnvironments.Command.activate(environment: "staging"))
        let document = StoreDocument(TransportMessage(kind: .command, pluginID: DebugDrawerEnvironments.pluginID, payload: payload))
        try layout.write(document.encoded(), to: layout.commands.appending(path: "0.json"))
        let indicator = EnvironmentIndicator(environments: app.environments)

        app.receiver.reevaluateGates()
        let duringSession = (backend.baseURL, indicator.environments.snapshot.isSwitched)
        app.sessions.end()

        #expect(duringSession == ("https://staging.api.example.com", true))
        #expect(backend.baseURL == "https://api.example.com")
        #expect(!indicator.environments.snapshot.isSwitched)
    }
}
