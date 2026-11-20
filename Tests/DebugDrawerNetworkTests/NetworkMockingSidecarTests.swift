// Network mocking as a sidecar reaches it: a real DebugDrawerReceiver serving the app-group store,
// the sidecar's DebugDrawerAppGroupStoreTransport (a debug-build type) on the same directory,
// opening sessions through the sessions' own model with grants the README's test signer issues,
// and a real URLSession configured as the README says, listing NetworkMockingURLProtocol, against
// a loopback server that answers what the real server would. The sessions run on a clock the test
// moves and a timer it fires, so expiry is exact. Each test waits for the audit entries its
// commands produce, which the sessions publish as the receiver performs each command file.
//
// The URL protocol reads the process's one route, so these tests are serialized: no other test's
// rules answer their requests.
#if DEBUG
    import Combine
    import CryptoKit
    import DebugDrawer
    @testable import DebugDrawerNetwork
    @testable import DebugDrawerReceiver
    import Foundation
    import Testing

    /// A host's remote configuration: one switch the test flips.
    @MainActor
    private final class RemoteSwitch {
        var isOn: Bool

        init(_ isOn: Bool) {
            self.isOn = isOn
        }
    }

    @MainActor
    @Suite(.serialized, .timeLimit(.minutes(1)))
    struct NetworkMockingSidecarTests {
        private static let start = Date(timeIntervalSince1970: 1_778_307_200)
        private static let audience = "com.example.MyApp"

        @Test("A rule for an allowed host answers only while the session is open: before it opens and after it ends, the server answers")
        func mocksOnlyDuringSession() async throws {
            let root = FileManager.default.temporaryDirectory.appending(path: "NetworkMockingSidecarTests-\(UUID().uuidString)")
            let store = root.appending(path: "Group/DebugDrawer")
            let serverKey = Curve25519.Signing.PrivateKey()
            let clock = MovableClock(Self.start)
            let policy = DebugDrawerGrantPolicy(
                verifier: DebugDrawerSignedGrantVerifier(keys: [.ed25519(serverKey.publicKey)]), audience: Self.audience
            )
            let sessions = DebugDrawerSessions(maximumDuration: 600, auditCapacity: 100, grantPolicy: policy, clock: clock, timer: ManualTimer())
            let mocking = NetworkMocking(
                sessions: sessions, allowedHosts: [.exact("127.0.0.1")],
                scheduler: ManualNetworkConditionScheduler(), random: FixedNetworkConditionRandomSource(0),
                now: { clock.now }, route: .shared
            )
            let receiver = DebugDrawerReceiver(directory: store, sessions: sessions)
            receiver.enable(.networkMocking(mocking))
            try receiver.start()
            defer { receiver.stop() }
            let server = try ScriptedServer { _ in "HTTP/1.1 200 OK\r\nContent-Length: 6\r\nConnection: close\r\n\r\nserver" }
            defer { server.stop() }
            let port = try await server.start()
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [NetworkMockingURLProtocol.self] + (configuration.protocolClasses ?? [])
            let urlSession = URLSession(configuration: configuration)
            defer { urlSession.invalidateAndCancel() }
            let url = try #require(URL(string: "http://127.0.0.1:\(port)/v1/greeting"))
            let grant = try DebugDrawerTestGrantSigner(key: serverKey).token(for: DebugDrawerGrant(
                id: "g-1", subject: "jane@example.com", audiences: [Self.audience], capabilities: [NetworkMocking.pluginID],
                notBefore: Self.start, expires: Self.start.addingTimeInterval(300)
            ))
            let rule = NetworkMockRule(
                name: "Greeting",
                matcher: .init(methods: ["GET"], host: .exact("127.0.0.1"), path: .exact("/v1/greeting")),
                response: .init(status: 201, body: .text("mocked"), contentType: "text/plain")
            )
            let sidecar = try DebugDrawerAppGroupStoreTransport(directory: AppGroupStoreLayout.appDirectory(inStore: store))
            let sessionControl = try await sidecar.connect(
                toPlugin: DebugDrawerSessions.pluginID, snapshot: DebugDrawerSessionState.self, command: DebugDrawerSessionCommand.self
            )
            let mocks = try await sidecar.connect(
                toPlugin: NetworkMocking.pluginID, snapshot: NetworkMocking.Snapshot.self, command: NetworkMocking.Command.self
            )
            let (auditEntries, auditEntry) = AsyncStream<DebugDrawerAuditEntry>.makeStream()
            let subscription = sessions.auditEntries.sink { auditEntry.yield($0) }
            defer { subscription.cancel() }
            var audit = auditEntries.makeAsyncIterator()

            let (before, _) = try await urlSession.data(from: url)
            mocks.send(.setRules([rule]))
            let refusedBeforeSession = await audit.next()
            sessionControl.send(.open(duration: 60, grant: grant))
            let opened = await audit.next()
            mocks.send(.setRules([rule]))
            let applied = await audit.next()
            let (during, duringResponse) = try await urlSession.data(from: url)
            let indicatorDuring = mocking.snapshot.isActive
            sessionControl.send(.end)
            var ending: DebugDrawerAuditEntry.Event?
            while let entry = await audit.next() {
                if case .sessionEnded = entry.event {
                    ending = entry.event
                    break
                }
            }
            let (after, _) = try await urlSession.data(from: url)

            #expect(String(bytes: before, encoding: .utf8) == "server")
            #expect(refusedBeforeSession?.event == .commandRefused(.noActiveSession))
            #expect(opened?.event == .sessionOpened(
                expires: Self.start.addingTimeInterval(60), grant: .init(id: "g-1", subject: "jane@example.com")
            ))
            #expect(applied?.capability == NetworkMocking.pluginID)
            #expect(applied?.event == .commandApplied)
            #expect(String(bytes: during, encoding: .utf8) == "mocked")
            #expect((duringResponse as? HTTPURLResponse)?.statusCode == 201)
            #expect((duringResponse as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") == "text/plain")
            #expect(indicatorDuring)
            #expect(ending == .sessionEnded(.ended))
            #expect(String(bytes: after, encoding: .utf8) == "server")
            #expect(mocking.snapshot.rules.isEmpty)
            #expect(!mocking.snapshot.isActive)
            #expect(server.requests.count == 2)
        }

        @Test("After the session's expiry the server answers, at the expiry date before the timer fires and once it has")
        func expiryEndsMocking() async throws {
            let root = FileManager.default.temporaryDirectory.appending(path: "NetworkMockingSidecarTests-\(UUID().uuidString)")
            let store = root.appending(path: "Group/DebugDrawer")
            let serverKey = Curve25519.Signing.PrivateKey()
            let clock = MovableClock(Self.start)
            let timer = ManualTimer()
            let policy = DebugDrawerGrantPolicy(
                verifier: DebugDrawerSignedGrantVerifier(keys: [.ed25519(serverKey.publicKey)]), audience: Self.audience
            )
            let sessions = DebugDrawerSessions(maximumDuration: 600, auditCapacity: 100, grantPolicy: policy, clock: clock, timer: timer)
            let mocking = NetworkMocking(
                sessions: sessions, allowedHosts: [.exact("127.0.0.1")],
                scheduler: ManualNetworkConditionScheduler(), random: FixedNetworkConditionRandomSource(0),
                now: { clock.now }, route: .shared
            )
            let receiver = DebugDrawerReceiver(directory: store, sessions: sessions)
            receiver.enable(.networkMocking(mocking))
            try receiver.start()
            defer { receiver.stop() }
            let server = try ScriptedServer { _ in "HTTP/1.1 200 OK\r\nContent-Length: 6\r\nConnection: close\r\n\r\nserver" }
            defer { server.stop() }
            let port = try await server.start()
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [NetworkMockingURLProtocol.self] + (configuration.protocolClasses ?? [])
            let urlSession = URLSession(configuration: configuration)
            defer { urlSession.invalidateAndCancel() }
            let url = try #require(URL(string: "http://127.0.0.1:\(port)/v1/greeting"))
            let grant = try DebugDrawerTestGrantSigner(key: serverKey).token(for: DebugDrawerGrant(
                id: "g-1", subject: "jane@example.com", audiences: [Self.audience], capabilities: [NetworkMocking.pluginID],
                notBefore: Self.start, expires: Self.start.addingTimeInterval(300)
            ))
            let rule = NetworkMockRule(
                name: "Greeting", matcher: .init(host: .exact("127.0.0.1"), path: .exact("/v1/greeting")), response: .init(body: .text("mocked"))
            )
            let sidecar = try DebugDrawerAppGroupStoreTransport(directory: AppGroupStoreLayout.appDirectory(inStore: store))
            let sessionControl = try await sidecar.connect(
                toPlugin: DebugDrawerSessions.pluginID, snapshot: DebugDrawerSessionState.self, command: DebugDrawerSessionCommand.self
            )
            let mocks = try await sidecar.connect(
                toPlugin: NetworkMocking.pluginID, snapshot: NetworkMocking.Snapshot.self, command: NetworkMocking.Command.self
            )
            let (auditEntries, auditEntry) = AsyncStream<DebugDrawerAuditEntry>.makeStream()
            let subscription = sessions.auditEntries.sink { auditEntry.yield($0) }
            defer { subscription.cancel() }
            var audit = auditEntries.makeAsyncIterator()

            sessionControl.send(.open(duration: 60, grant: grant))
            _ = await audit.next()
            mocks.send(.setRules([rule]))
            let applied = await audit.next()
            let (during, _) = try await urlSession.data(from: url)
            clock.set(Self.start.addingTimeInterval(60))
            let (atExpiry, _) = try await urlSession.data(from: url)
            let rulesBeforeTimer = mocking.snapshot.rules.count
            timer.fireNow()
            let (afterTimer, _) = try await urlSession.data(from: url)

            #expect(applied?.event == .commandApplied)
            #expect(String(bytes: during, encoding: .utf8) == "mocked")
            #expect(String(bytes: atExpiry, encoding: .utf8) == "server")
            #expect(rulesBeforeTimer == 1)
            #expect(sessions.snapshot.session == nil)
            #expect(mocking.snapshot.rules.isEmpty)
            #expect(String(bytes: afterTimer, encoding: .utf8) == "server")
            #expect(server.requests.count == 2)
        }

        @Test("A rule for a host the app doesn't allow never answers, even in a session, while the same rule answers an allowed host")
        func disallowedHostNeverMocked() async throws {
            let root = FileManager.default.temporaryDirectory.appending(path: "NetworkMockingSidecarTests-\(UUID().uuidString)")
            let store = root.appending(path: "Group/DebugDrawer")
            let serverKey = Curve25519.Signing.PrivateKey()
            let clock = MovableClock(Self.start)
            let policy = DebugDrawerGrantPolicy(
                verifier: DebugDrawerSignedGrantVerifier(keys: [.ed25519(serverKey.publicKey)]), audience: Self.audience
            )
            let sessions = DebugDrawerSessions(maximumDuration: 600, auditCapacity: 100, grantPolicy: policy, clock: clock, timer: ManualTimer())
            let mocking = NetworkMocking(
                sessions: sessions, allowedHosts: [.exact("127.0.0.1")],
                scheduler: ManualNetworkConditionScheduler(), random: FixedNetworkConditionRandomSource(0),
                now: { clock.now }, route: .shared
            )
            let receiver = DebugDrawerReceiver(directory: store, sessions: sessions)
            receiver.enable(.networkMocking(mocking))
            try receiver.start()
            defer { receiver.stop() }
            let server = try ScriptedServer { _ in "HTTP/1.1 200 OK\r\nContent-Length: 6\r\nConnection: close\r\n\r\nserver" }
            defer { server.stop() }
            let port = try await server.start()
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [NetworkMockingURLProtocol.self] + (configuration.protocolClasses ?? [])
            let urlSession = URLSession(configuration: configuration)
            defer { urlSession.invalidateAndCancel() }
            // `localhost` reaches the same loopback server under a host the app didn't allow.
            let disallowed = try #require(URL(string: "http://localhost:\(port)/v1/greeting"))
            let allowed = try #require(URL(string: "http://127.0.0.1:\(port)/v1/greeting"))
            let grant = try DebugDrawerTestGrantSigner(key: serverKey).token(for: DebugDrawerGrant(
                id: "g-1", subject: "jane@example.com", audiences: [Self.audience], capabilities: [NetworkMocking.pluginID],
                notBefore: Self.start, expires: Self.start.addingTimeInterval(300)
            ))
            let rules = [
                NetworkMockRule(name: "Named", matcher: .init(host: .exact("localhost")), response: .init(body: .text("mocked by name"))),
                NetworkMockRule(name: "Any host", matcher: .init(host: .any, path: .exact("/v1/greeting")), response: .init(body: .text("mocked")))
            ]
            let sidecar = try DebugDrawerAppGroupStoreTransport(directory: AppGroupStoreLayout.appDirectory(inStore: store))
            let sessionControl = try await sidecar.connect(
                toPlugin: DebugDrawerSessions.pluginID, snapshot: DebugDrawerSessionState.self, command: DebugDrawerSessionCommand.self
            )
            let mocks = try await sidecar.connect(
                toPlugin: NetworkMocking.pluginID, snapshot: NetworkMocking.Snapshot.self, command: NetworkMocking.Command.self
            )
            let (auditEntries, auditEntry) = AsyncStream<DebugDrawerAuditEntry>.makeStream()
            let subscription = sessions.auditEntries.sink { auditEntry.yield($0) }
            defer { subscription.cancel() }
            var audit = auditEntries.makeAsyncIterator()

            sessionControl.send(.open(duration: 60, grant: grant))
            _ = await audit.next()
            mocks.send(.setRules(rules))
            let applied = await audit.next()
            let (toDisallowed, _) = try await urlSession.data(from: disallowed)
            let (toAllowed, _) = try await urlSession.data(from: allowed)

            #expect(applied?.event == .commandApplied)
            #expect(String(bytes: toDisallowed, encoding: .utf8) == "server")
            #expect(String(bytes: toAllowed, encoding: .utf8) == "mocked")
            #expect(server.requests.count == 1)
        }

        @Test("With an empty allowlist nothing is mocked, even in a session with rules for every host")
        func emptyAllowlistMocksNothing() async throws {
            let root = FileManager.default.temporaryDirectory.appending(path: "NetworkMockingSidecarTests-\(UUID().uuidString)")
            let store = root.appending(path: "Group/DebugDrawer")
            let serverKey = Curve25519.Signing.PrivateKey()
            let clock = MovableClock(Self.start)
            let policy = DebugDrawerGrantPolicy(
                verifier: DebugDrawerSignedGrantVerifier(keys: [.ed25519(serverKey.publicKey)]), audience: Self.audience
            )
            let sessions = DebugDrawerSessions(maximumDuration: 600, auditCapacity: 100, grantPolicy: policy, clock: clock, timer: ManualTimer())
            let mocking = NetworkMocking(
                sessions: sessions, allowedHosts: [],
                scheduler: ManualNetworkConditionScheduler(), random: FixedNetworkConditionRandomSource(0),
                now: { clock.now }, route: .shared
            )
            let receiver = DebugDrawerReceiver(directory: store, sessions: sessions)
            receiver.enable(.networkMocking(mocking))
            try receiver.start()
            defer { receiver.stop() }
            let server = try ScriptedServer { _ in "HTTP/1.1 200 OK\r\nContent-Length: 6\r\nConnection: close\r\n\r\nserver" }
            defer { server.stop() }
            let port = try await server.start()
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [NetworkMockingURLProtocol.self] + (configuration.protocolClasses ?? [])
            let urlSession = URLSession(configuration: configuration)
            defer { urlSession.invalidateAndCancel() }
            let url = try #require(URL(string: "http://127.0.0.1:\(port)/v1/greeting"))
            let grant = try DebugDrawerTestGrantSigner(key: serverKey).token(for: DebugDrawerGrant(
                id: "g-1", subject: "jane@example.com", audiences: [Self.audience], capabilities: [NetworkMocking.pluginID],
                notBefore: Self.start, expires: Self.start.addingTimeInterval(300)
            ))
            let rule = NetworkMockRule(name: "Everything", matcher: .init(), response: .init(body: .text("mocked")))
            let sidecar = try DebugDrawerAppGroupStoreTransport(directory: AppGroupStoreLayout.appDirectory(inStore: store))
            let sessionControl = try await sidecar.connect(
                toPlugin: DebugDrawerSessions.pluginID, snapshot: DebugDrawerSessionState.self, command: DebugDrawerSessionCommand.self
            )
            let mocks = try await sidecar.connect(
                toPlugin: NetworkMocking.pluginID, snapshot: NetworkMocking.Snapshot.self, command: NetworkMocking.Command.self
            )
            let (auditEntries, auditEntry) = AsyncStream<DebugDrawerAuditEntry>.makeStream()
            let subscription = sessions.auditEntries.sink { auditEntry.yield($0) }
            defer { subscription.cancel() }
            var audit = auditEntries.makeAsyncIterator()

            sessionControl.send(.open(duration: 60, grant: grant))
            _ = await audit.next()
            mocks.send(.setRules([rule]))
            let applied = await audit.next()
            let (data, _) = try await urlSession.data(from: url)

            #expect(applied?.event == .commandApplied)
            #expect(mocking.snapshot.rules == [rule])
            #expect(!mocking.snapshot.isActive)
            #expect(String(bytes: data, encoding: .utf8) == "server")
            #expect(server.requests.count == 1)
        }

        @Test("With a grant policy, a session opened without a grant, or with one not listing network mocking, has its rules refused")
        func grantRequiredUnderPolicy() async throws {
            let root = FileManager.default.temporaryDirectory.appending(path: "NetworkMockingSidecarTests-\(UUID().uuidString)")
            let store = root.appending(path: "Group/DebugDrawer")
            let serverKey = Curve25519.Signing.PrivateKey()
            let clock = MovableClock(Self.start)
            let policy = DebugDrawerGrantPolicy(
                verifier: DebugDrawerSignedGrantVerifier(keys: [.ed25519(serverKey.publicKey)]), audience: Self.audience
            )
            let sessions = DebugDrawerSessions(maximumDuration: 600, auditCapacity: 100, grantPolicy: policy, clock: clock, timer: ManualTimer())
            let mocking = NetworkMocking(
                sessions: sessions, allowedHosts: [.exact("127.0.0.1")],
                scheduler: ManualNetworkConditionScheduler(), random: FixedNetworkConditionRandomSource(0),
                now: { clock.now }, route: .shared
            )
            let receiver = DebugDrawerReceiver(directory: store, sessions: sessions)
            receiver.enable(.networkMocking(mocking))
            try receiver.start()
            defer { receiver.stop() }
            let server = try ScriptedServer { _ in "HTTP/1.1 200 OK\r\nContent-Length: 6\r\nConnection: close\r\n\r\nserver" }
            defer { server.stop() }
            let port = try await server.start()
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [NetworkMockingURLProtocol.self] + (configuration.protocolClasses ?? [])
            let urlSession = URLSession(configuration: configuration)
            defer { urlSession.invalidateAndCancel() }
            let url = try #require(URL(string: "http://127.0.0.1:\(port)/v1/greeting"))
            let otherCapability = try DebugDrawerTestGrantSigner(key: serverKey).token(for: DebugDrawerGrant(
                id: "g-2", subject: "jane@example.com", audiences: [Self.audience], capabilities: [DebugDrawerFeatureFlagOverrides.pluginID],
                notBefore: Self.start, expires: Self.start.addingTimeInterval(300)
            ))
            let rule = NetworkMockRule(name: "Greeting", matcher: .init(host: .exact("127.0.0.1")), response: .init(body: .text("mocked")))
            let sidecar = try DebugDrawerAppGroupStoreTransport(directory: AppGroupStoreLayout.appDirectory(inStore: store))
            let sessionControl = try await sidecar.connect(
                toPlugin: DebugDrawerSessions.pluginID, snapshot: DebugDrawerSessionState.self, command: DebugDrawerSessionCommand.self
            )
            let mocks = try await sidecar.connect(
                toPlugin: NetworkMocking.pluginID, snapshot: NetworkMocking.Snapshot.self, command: NetworkMocking.Command.self
            )
            let (auditEntries, auditEntry) = AsyncStream<DebugDrawerAuditEntry>.makeStream()
            let subscription = sessions.auditEntries.sink { auditEntry.yield($0) }
            defer { subscription.cancel() }
            var audit = auditEntries.makeAsyncIterator()

            sessionControl.send(.open(duration: 60))
            let openWithout = await audit.next()
            mocks.send(.setRules([rule]))
            let withoutGrant = await audit.next()
            let (afterWithout, _) = try await urlSession.data(from: url)
            sessionControl.send(.open(duration: 60, grant: otherCapability))
            let openWithOther = await audit.next()
            mocks.send(.setRules([rule]))
            let withOtherGrant = await audit.next()
            let (afterOther, _) = try await urlSession.data(from: url)

            #expect(openWithout?.event == .commandRefused(.grantMissing))
            #expect(withoutGrant?.event == .commandRefused(.noActiveSession))
            #expect(String(bytes: afterWithout, encoding: .utf8) == "server")
            #expect(openWithOther?.event == .sessionOpened(
                expires: Self.start.addingTimeInterval(60), grant: .init(id: "g-2", subject: "jane@example.com")
            ))
            #expect(withOtherGrant?.capability == NetworkMocking.pluginID)
            #expect(withOtherGrant?.event == .commandRefused(.capabilityNotGranted))
            #expect(mocking.snapshot.rules.isEmpty)
            #expect(String(bytes: afterOther, encoding: .utf8) == "server")
            #expect(server.requests.count == 2)
        }

        @Test("With no grant policy, the capability requires a grant all the same: its rules are refused as grantMissing in an open session")
        func grantRequiredWithoutPolicy() async throws {
            let root = FileManager.default.temporaryDirectory.appending(path: "NetworkMockingSidecarTests-\(UUID().uuidString)")
            let store = root.appending(path: "Group/DebugDrawer")
            let clock = MovableClock(Self.start)
            let sessions = DebugDrawerSessions(maximumDuration: 600, auditCapacity: 100, clock: clock, timer: ManualTimer())
            let mocking = NetworkMocking(
                sessions: sessions, allowedHosts: [.exact("127.0.0.1")],
                scheduler: ManualNetworkConditionScheduler(), random: FixedNetworkConditionRandomSource(0),
                now: { clock.now }, route: .shared
            )
            let receiver = DebugDrawerReceiver(directory: store, sessions: sessions)
            receiver.enable(.networkMocking(mocking))
            try receiver.start()
            defer { receiver.stop() }
            let server = try ScriptedServer { _ in "HTTP/1.1 200 OK\r\nContent-Length: 6\r\nConnection: close\r\n\r\nserver" }
            defer { server.stop() }
            let port = try await server.start()
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [NetworkMockingURLProtocol.self] + (configuration.protocolClasses ?? [])
            let urlSession = URLSession(configuration: configuration)
            defer { urlSession.invalidateAndCancel() }
            let url = try #require(URL(string: "http://127.0.0.1:\(port)/v1/greeting"))
            let rule = NetworkMockRule(name: "Greeting", matcher: .init(host: .exact("127.0.0.1")), response: .init(body: .text("mocked")))
            let sidecar = try DebugDrawerAppGroupStoreTransport(directory: AppGroupStoreLayout.appDirectory(inStore: store))
            let sessionControl = try await sidecar.connect(
                toPlugin: DebugDrawerSessions.pluginID, snapshot: DebugDrawerSessionState.self, command: DebugDrawerSessionCommand.self
            )
            let mocks = try await sidecar.connect(
                toPlugin: NetworkMocking.pluginID, snapshot: NetworkMocking.Snapshot.self, command: NetworkMocking.Command.self
            )
            let (auditEntries, auditEntry) = AsyncStream<DebugDrawerAuditEntry>.makeStream()
            let subscription = sessions.auditEntries.sink { auditEntry.yield($0) }
            defer { subscription.cancel() }
            var audit = auditEntries.makeAsyncIterator()

            sessionControl.send(.open(duration: 60))
            let opened = await audit.next()
            mocks.send(.setRules([rule]))
            let refused = await audit.next()
            let (data, _) = try await urlSession.data(from: url)

            #expect(opened?.event == .sessionOpened(expires: Self.start.addingTimeInterval(60), grant: nil))
            #expect(refused?.capability == NetworkMocking.pluginID)
            #expect(refused?.event == .commandRefused(.grantMissing))
            #expect(mocking.snapshot.rules.isEmpty)
            #expect(String(bytes: data, encoding: .utf8) == "server")
            #expect(server.requests.count == 1)
        }

        @Test("A regular expression or a file body from the sidecar is refused as malformed, and nothing is mocked")
        func expressionsAndFilesRefused() async throws {
            let root = FileManager.default.temporaryDirectory.appending(path: "NetworkMockingSidecarTests-\(UUID().uuidString)")
            let store = root.appending(path: "Group/DebugDrawer")
            let serverKey = Curve25519.Signing.PrivateKey()
            let clock = MovableClock(Self.start)
            let policy = DebugDrawerGrantPolicy(
                verifier: DebugDrawerSignedGrantVerifier(keys: [.ed25519(serverKey.publicKey)]), audience: Self.audience
            )
            let sessions = DebugDrawerSessions(maximumDuration: 600, auditCapacity: 100, grantPolicy: policy, clock: clock, timer: ManualTimer())
            let mocking = NetworkMocking(
                sessions: sessions, allowedHosts: [.exact("127.0.0.1")],
                scheduler: ManualNetworkConditionScheduler(), random: FixedNetworkConditionRandomSource(0),
                now: { clock.now }, route: .shared
            )
            let receiver = DebugDrawerReceiver(directory: store, sessions: sessions)
            receiver.enable(.networkMocking(mocking))
            try receiver.start()
            defer { receiver.stop() }
            let grant = try DebugDrawerTestGrantSigner(key: serverKey).token(for: DebugDrawerGrant(
                id: "g-1", subject: "jane@example.com", audiences: [Self.audience], capabilities: [NetworkMocking.pluginID],
                notBefore: Self.start, expires: Self.start.addingTimeInterval(300)
            ))
            let commands: [NetworkMocking.Command] = [
                .setRules([NetworkMockRule(name: "Regex host", matcher: .init(host: .regex(".*")), response: .init())]),
                .setRules([NetworkMockRule(
                    name: "Regex path", matcher: .init(host: .exact("127.0.0.1"), path: .regex("/v1/.*")), response: .init()
                )]),
                .setRules([NetworkMockRule(name: "File", matcher: .init(host: .exact("127.0.0.1")), response: .init(body: .file("greeting.json")))]),
                .setConditions([NetworkConditionProfile(name: "Regex", host: .regex(".*"), latency: .seconds(1))])
            ]
            let sidecar = try DebugDrawerAppGroupStoreTransport(directory: AppGroupStoreLayout.appDirectory(inStore: store))
            let sessionControl = try await sidecar.connect(
                toPlugin: DebugDrawerSessions.pluginID, snapshot: DebugDrawerSessionState.self, command: DebugDrawerSessionCommand.self
            )
            let mocks = try await sidecar.connect(
                toPlugin: NetworkMocking.pluginID, snapshot: NetworkMocking.Snapshot.self, command: NetworkMocking.Command.self
            )
            let (auditEntries, auditEntry) = AsyncStream<DebugDrawerAuditEntry>.makeStream()
            let subscription = sessions.auditEntries.sink { auditEntry.yield($0) }
            defer { subscription.cancel() }
            var audit = auditEntries.makeAsyncIterator()

            sessionControl.send(.open(duration: 60, grant: grant))
            _ = await audit.next()
            var refusals: [DebugDrawerAuditEntry.Event] = []
            for command in commands {
                mocks.send(command)
                if let entry = await audit.next() {
                    refusals.append(entry.event)
                }
            }

            let expected = Array(repeating: DebugDrawerAuditEntry.Event.commandRefused(.malformedCommand), count: commands.count)
            #expect(refusals == expected)
            #expect(mocking.snapshot.rules.isEmpty)
            #expect(mocking.snapshot.conditions.isEmpty)
        }

        @Test("Turning the capability's gate off reverts its rules at once, while the session goes on")
        func capabilityGateReverts() async throws {
            let root = FileManager.default.temporaryDirectory.appending(path: "NetworkMockingSidecarTests-\(UUID().uuidString)")
            let store = root.appending(path: "Group/DebugDrawer")
            let serverKey = Curve25519.Signing.PrivateKey()
            let clock = MovableClock(Self.start)
            let policy = DebugDrawerGrantPolicy(
                verifier: DebugDrawerSignedGrantVerifier(keys: [.ed25519(serverKey.publicKey)]), audience: Self.audience
            )
            let sessions = DebugDrawerSessions(maximumDuration: 600, auditCapacity: 100, grantPolicy: policy, clock: clock, timer: ManualTimer())
            let mocking = NetworkMocking(
                sessions: sessions, allowedHosts: [.exact("127.0.0.1")],
                scheduler: ManualNetworkConditionScheduler(), random: FixedNetworkConditionRandomSource(0),
                now: { clock.now }, route: .shared
            )
            let gate = RemoteSwitch(true)
            let receiver = DebugDrawerReceiver(directory: store, sessions: sessions)
            receiver.enable(.networkMocking(mocking)) { gate.isOn }
            try receiver.start()
            defer { receiver.stop() }
            let server = try ScriptedServer { _ in "HTTP/1.1 200 OK\r\nContent-Length: 6\r\nConnection: close\r\n\r\nserver" }
            defer { server.stop() }
            let port = try await server.start()
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [NetworkMockingURLProtocol.self] + (configuration.protocolClasses ?? [])
            let urlSession = URLSession(configuration: configuration)
            defer { urlSession.invalidateAndCancel() }
            let url = try #require(URL(string: "http://127.0.0.1:\(port)/v1/greeting"))
            let grant = try DebugDrawerTestGrantSigner(key: serverKey).token(for: DebugDrawerGrant(
                id: "g-1", subject: "jane@example.com", audiences: [Self.audience], capabilities: [NetworkMocking.pluginID],
                notBefore: Self.start, expires: Self.start.addingTimeInterval(300)
            ))
            let rule = NetworkMockRule(name: "Greeting", matcher: .init(host: .exact("127.0.0.1")), response: .init(body: .text("mocked")))
            let sidecar = try DebugDrawerAppGroupStoreTransport(directory: AppGroupStoreLayout.appDirectory(inStore: store))
            let sessionControl = try await sidecar.connect(
                toPlugin: DebugDrawerSessions.pluginID, snapshot: DebugDrawerSessionState.self, command: DebugDrawerSessionCommand.self
            )
            let mocks = try await sidecar.connect(
                toPlugin: NetworkMocking.pluginID, snapshot: NetworkMocking.Snapshot.self, command: NetworkMocking.Command.self
            )
            let (auditEntries, auditEntry) = AsyncStream<DebugDrawerAuditEntry>.makeStream()
            let subscription = sessions.auditEntries.sink { auditEntry.yield($0) }
            defer { subscription.cancel() }
            var audit = auditEntries.makeAsyncIterator()

            sessionControl.send(.open(duration: 60, grant: grant))
            _ = await audit.next()
            mocks.send(.setRules([rule]))
            _ = await audit.next()
            let (during, _) = try await urlSession.data(from: url)
            gate.isOn = false
            receiver.reevaluateGates()
            let reverted = await audit.next()
            let (afterGate, _) = try await urlSession.data(from: url)

            #expect(String(bytes: during, encoding: .utf8) == "mocked")
            #expect(reverted?.event == .changeReverted)
            #expect(sessions.snapshot.isActive)
            #expect(mocking.snapshot.rules.isEmpty)
            #expect(String(bytes: afterGate, encoding: .utf8) == "server")
        }
    }
#endif
