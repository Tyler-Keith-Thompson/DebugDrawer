// The README's "Network mocks in production" examples, verbatim, so the README cannot drift from
// the code: the app's setup, the sidecar's rule and the indicator. The request goes through the
// process's one route, so the test is part of the serialized NetworkMockingSidecarTests suite; the
// rule answers it, so nothing reaches the network.
#if DEBUG
    import CryptoKit
    import DebugDrawer
    import DebugDrawerNetwork
    import DebugDrawerReceiver
    import Foundation
    import SwiftUI
    import Testing

    @MainActor
    final class ProductionNetworkMocking {
        let sessions: DebugDrawerSessions
        let receiver: DebugDrawerReceiver
        let mocking: NetworkMocking
        let apiSession: URLSession

        init(grantServerKey: Curve25519.Signing.PublicKey, container: URL) throws {
            sessions = DebugDrawerSessions(maximumDuration: 15 * 60, grantPolicy: DebugDrawerGrantPolicy(
                verifier: DebugDrawerSignedGrantVerifier(keys: [.ed25519(grantServerKey)]),
                audience: "com.example.MyApp"
            ))
            mocking = NetworkMocking(sessions: sessions, allowedHosts: [.exact("api.example.com"), .domain("staging.example.com")])
            receiver = DebugDrawerReceiver(directory: container.appending(path: "DebugDrawer"), sessions: sessions)
            receiver.enable(.networkMocking(mocking))
            try receiver.start()

            let configuration = URLSessionConfiguration.default
            configuration.protocolClasses = [NetworkMockingURLProtocol.self] + (configuration.protocolClasses ?? [])
            apiSession = URLSession(configuration: configuration)
        }
    }

    struct NetworkMockingIndicator: View {
        @ObservedObject var mocking: NetworkMocking

        var body: some View {
            if mocking.snapshot.isActive {
                Label("Network mocking active", systemImage: "exclamationmark.icloud")
            }
        }
    }

    extension NetworkMockingSidecarTests {
        @Test("README: a granted session's rule answers the app's configured session, and the indicator shows it")
        func readmeNetworkMocksInProduction() async throws {
            let container = FileManager.default.temporaryDirectory.appending(path: "READMENetworkMocking-\(UUID().uuidString)")
            let serverKey = Curve25519.Signing.PrivateKey()
            let app = try ProductionNetworkMocking(grantServerKey: serverKey.publicKey, container: container)
            defer { app.receiver.stop() }
            let grantFromServer = try DebugDrawerTestGrantSigner(key: serverKey).token(for: DebugDrawerGrant(
                id: UUID().uuidString, subject: "jane@example.com", audiences: ["com.example.MyApp"],
                capabilities: [NetworkMocking.pluginID],
                notBefore: Date(), expires: Date().addingTimeInterval(10 * 60)
            ))
            let appDirectory = AppGroupStoreLayout.appDirectory(inStore: container.appending(path: "DebugDrawer"))
            let sidecar = try DebugDrawerAppGroupStoreTransport(directory: appDirectory)
            let sessionControl = try await sidecar.connect(
                toPlugin: DebugDrawerSessions.pluginID, snapshot: DebugDrawerSessionState.self, command: DebugDrawerSessionCommand.self
            )
            let mocks = try await sidecar.connect(
                toPlugin: NetworkMocking.pluginID, snapshot: NetworkMocking.Snapshot.self, command: NetworkMocking.Command.self
            )
            let (arrivals, arrival) = AsyncStream<DebugDrawerAuditEntry>.makeStream()
            let subscription = app.sessions.auditEntries.sink { arrival.yield($0) }
            defer { subscription.cancel() }
            var recorded = arrivals.makeAsyncIterator()
            let url = try #require(URL(string: "https://api.example.com/v1/orders/42"))

            sessionControl.send(.open(duration: 15 * 60, grant: grantFromServer))
            _ = await recorded.next()
            // In the sidecar, once its session is open:
            mocks.send(.setRules([NetworkMockRule(
                name: "Orders outage",
                matcher: .init(methods: ["GET"], host: .exact("api.example.com"), path: .wildcard("/v1/orders/**")),
                response: .init(status: 503, body: .text(#"{"error":"maintenance"}"#), contentType: "application/json")
            )]))
            let applied = await recorded.next()
            let (data, response) = try await app.apiSession.data(from: url)
            let indicator = NetworkMockingIndicator(mocking: app.mocking)

            #expect(applied?.event == .commandApplied)
            #expect((response as? HTTPURLResponse)?.statusCode == 503)
            #expect(String(bytes: data, encoding: .utf8) == #"{"error":"maintenance"}"#)
            #expect(indicator.mocking.snapshot.isActive)
        }
    }
#endif
