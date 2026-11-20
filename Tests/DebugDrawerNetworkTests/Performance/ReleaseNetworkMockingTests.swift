// The release build. `--config=release` builds and runs only the performance targets, so this is
// where the capability is tested compiled without DEBUG, as a production app's build is: through
// the public API, a real receiver whose sessions verify a grant the README's test signer issued, and
// the command files a sidecar leaves in its store (the sidecar's transports are debug-build types).
// It shows that nothing is registered or replaced in release: only the session the host configured
// is answered from the rules. Nothing listens on the discard port, so a request the rules don't
// answer fails to connect. In debug the file is empty; NetworkMockingSidecarTests and
// NetworkMockingIsolationTests cover the same through the sidecar's transport and a real server.
#if !DEBUG
    import CryptoKit
    import DebugDrawerNetwork
    import DebugDrawerReceiver
    import Foundation
    import ObjectiveC
    import Testing

    @MainActor
    @Suite(.serialized, .timeLimit(.minutes(1)))
    struct ReleaseNetworkMockingTests {
        @Test("In release, a granted rule answers only the session the host configured, nothing is registered or replaced, and the end stops it")
        func answersOnlyTheConfiguredSession() async throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: "ReleaseNetworkMockingTests-\(UUID().uuidString)")
            let layout = AppGroupStoreLayout(directory: directory)
            #expect(layout.create())
            let serverKey = Curve25519.Signing.PrivateKey()
            let now = Date()
            let grant = try DebugDrawerTestGrantSigner(key: serverKey).token(for: DebugDrawerGrant(
                id: "release-1", subject: "jane@example.com", audiences: ["com.example.MyApp"], capabilities: [NetworkMocking.pluginID],
                notBefore: now.addingTimeInterval(-10), expires: now.addingTimeInterval(300)
            ))
            let rule = NetworkMockRule(
                name: "Greeting", matcher: .init(host: .exact("127.0.0.1"), path: .exact("/v1/greeting")), response: .init(body: .text("mocked"))
            )
            let commands: [(String, Data)] = try [
                (DebugDrawerSessions.pluginID, TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60, grant: grant))),
                (NetworkMocking.pluginID, TransportMessage.payload(NetworkMocking.Command.setRules([rule])))
            ]
            for (index, (id, payload)) in commands.enumerated() {
                let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
                try layout.write(document.encoded(), to: layout.commands.appending(path: "\(index).json"))
            }
            let getter = try #require(class_getInstanceMethod(
                URLSessionConfiguration.self, #selector(getter: URLSessionConfiguration.protocolClasses)
            ))
            let expectedGetter = method_getImplementation(getter)
            let sessions = DebugDrawerSessions(maximumDuration: 300, grantPolicy: DebugDrawerGrantPolicy(
                verifier: DebugDrawerSignedGrantVerifier(keys: [.ed25519(serverKey.publicKey)]), audience: "com.example.MyApp"
            ))
            let mocking = NetworkMocking(sessions: sessions, allowedHosts: [.exact("127.0.0.1")])
            let receiver = DebugDrawerReceiver(directory: directory, sessions: sessions)
            receiver.enable(.networkMocking(mocking))
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [NetworkMockingURLProtocol.self] + (configuration.protocolClasses ?? [])
            let configured = URLSession(configuration: configuration)
            defer { configured.invalidateAndCancel() }
            let url = try #require(URL(string: "http://127.0.0.1:9/v1/greeting"))
            func body(from session: URLSession) async -> String {
                do {
                    let (data, _) = try await session.data(from: url)
                    return String(bytes: data, encoding: .utf8) ?? ""
                } catch {
                    return "not answered"
                }
            }

            try receiver.start()
            defer { receiver.stop() }
            let isActive = mocking.snapshot.isActive
            let fromConfigured = await body(from: configured)
            let fromShared = await body(from: URLSession.shared)
            let listings = [URLSessionConfiguration.default, .ephemeral, URLSession.shared.configuration].map { listed in
                (listed.protocolClasses ?? []).contains { $0 == NetworkMockingURLProtocol.self }
            }
            sessions.end()
            let afterEnd = await body(from: configured)

            #expect(isActive)
            #expect(fromConfigured == "mocked")
            #expect(fromShared == "not answered")
            #expect(listings == [false, false, false])
            #expect(method_getImplementation(getter) == expectedGetter)
            #expect(afterEnd == "not answered")
            #expect(!mocking.snapshot.isActive)
        }

        @Test("In release, without a grant policy the capability's rules are refused, and nothing is answered")
        func refusedWithoutGrants() async throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: "ReleaseNetworkMockingTests-\(UUID().uuidString)")
            let layout = AppGroupStoreLayout(directory: directory)
            #expect(layout.create())
            let rule = NetworkMockRule(name: "Everything", matcher: .init(), response: .init(body: .text("mocked")))
            let commands: [(String, Data)] = try [
                (DebugDrawerSessions.pluginID, TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60))),
                (NetworkMocking.pluginID, TransportMessage.payload(NetworkMocking.Command.setRules([rule])))
            ]
            for (index, (id, payload)) in commands.enumerated() {
                let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
                try layout.write(document.encoded(), to: layout.commands.appending(path: "\(index).json"))
            }
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let mocking = NetworkMocking(sessions: sessions, allowedHosts: [.exact("127.0.0.1")])
            let receiver = DebugDrawerReceiver(directory: directory, sessions: sessions)
            receiver.enable(.networkMocking(mocking))
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [NetworkMockingURLProtocol.self] + (configuration.protocolClasses ?? [])
            let configured = URLSession(configuration: configuration)
            defer { configured.invalidateAndCancel() }
            let url = try #require(URL(string: "http://127.0.0.1:9/v1/greeting"))

            try receiver.start()
            defer { receiver.stop() }
            let answered: String
            do {
                let (data, _) = try await configured.data(from: url)
                answered = String(bytes: data, encoding: .utf8) ?? ""
            } catch {
                answered = "not answered"
            }

            #expect(sessions.snapshot.isActive)
            #expect(sessions.auditLog.last?.event == .commandRefused(.grantMissing))
            #expect(mocking.snapshot.rules.isEmpty)
            #expect(answered == "not answered")
        }
    }
#endif
