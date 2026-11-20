// What the capability leaves alone: it registers nothing with URL loading and replaces no method,
// so a session the host didn't configure, URLSession.shared included, reaches the server while a
// session's rules are in effect. These requests go through the process's one route, so they are
// part of the serialized NetworkMockingSidecarTests suite.
#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerNetwork
    @testable import DebugDrawerReceiver
    import Foundation
    import ObjectiveC
    import Testing

    extension NetworkMockingSidecarTests {
        @Test("With rules in effect, no configuration lists the URL protocol unless the host added it, and URLSession.shared reaches the server")
        func unconfiguredSessionsUntouched() async throws {
            let clock = MovableClock(Date(timeIntervalSince1970: 1_778_307_200))
            let sessions = DebugDrawerSessions(maximumDuration: 600, auditCapacity: 100, clock: clock, timer: ManualTimer())
            let getter = try #require(class_getInstanceMethod(
                URLSessionConfiguration.self, #selector(getter: URLSessionConfiguration.protocolClasses)
            ))
            let expectedGetter = method_getImplementation(getter)
            let server = try ScriptedServer { _ in "HTTP/1.1 200 OK\r\nContent-Length: 6\r\nConnection: close\r\n\r\nserver" }
            defer { server.stop() }
            let port = try await server.start()
            let url = try #require(URL(string: "http://127.0.0.1:\(port)/v1/greeting"))
            let receiver = DebugDrawerReceiver(
                directory: FileManager.default.temporaryDirectory.appending(path: "NetworkMockingIsolationTests-\(UUID().uuidString)"),
                sessions: sessions
            )
            let mocking = NetworkMocking(
                sessions: sessions, allowedHosts: [.exact("127.0.0.1")],
                scheduler: ManualNetworkConditionScheduler(), random: FixedNetworkConditionRandomSource(0), now: { clock.now }, route: .shared
            )
            receiver.enable(.networkMocking(mocking))
            sessions.perform(.open(duration: 60))
            defer { sessions.end() }
            mocking.perform(.setRules([NetworkMockRule(name: "Everything", matcher: .init(), response: .init(body: .text("mocked")))]))
            let configured = URLSessionConfiguration.ephemeral
            configured.protocolClasses = [NetworkMockingURLProtocol.self] + (configured.protocolClasses ?? [])
            let configuredSession = URLSession(configuration: configured)
            defer { configuredSession.invalidateAndCancel() }
            let ephemeralSession = URLSession(configuration: .ephemeral)
            defer { ephemeralSession.invalidateAndCancel() }

            let listings = [URLSessionConfiguration.default, .ephemeral, URLSession.shared.configuration].map { configuration in
                (configuration.protocolClasses ?? []).contains { $0 == NetworkMockingURLProtocol.self }
            }
            let (shared, _) = try await URLSession.shared.data(from: url)
            let (ephemeral, _) = try await ephemeralSession.data(from: url)
            let (mocked, _) = try await configuredSession.data(from: url)

            #expect(mocking.snapshot.isActive)
            #expect(listings == [false, false, false])
            #expect(method_getImplementation(getter) == expectedGetter)
            #expect(String(bytes: shared, encoding: .utf8) == "server")
            #expect(String(bytes: ephemeral, encoding: .utf8) == "server")
            #expect(String(bytes: mocked, encoding: .utf8) == "mocked")
            #expect(server.requests.count == 2)
        }

        @Test("The URL protocol declines a WebSocket task, so its handshake reaches the server")
        func webSocketDeclined() throws {
            let clock = MovableClock(Date(timeIntervalSince1970: 1_778_307_200))
            let sessions = DebugDrawerSessions(maximumDuration: 600, auditCapacity: 100, clock: clock, timer: ManualTimer())
            let mocking = NetworkMocking(
                sessions: sessions, allowedHosts: [.exact("127.0.0.1")],
                scheduler: ManualNetworkConditionScheduler(), random: FixedNetworkConditionRandomSource(0), now: { clock.now }, route: .shared
            )
            sessions.perform(.open(duration: 60))
            defer { sessions.end() }
            mocking.perform(.setRules([NetworkMockRule(name: "Everything", matcher: .init(), response: .init(body: .text("mocked")))]))
            let session = URLSession(configuration: .ephemeral)
            defer { session.invalidateAndCancel() }
            let socketURL = try #require(URL(string: "ws://127.0.0.1:9/socket"))
            let dataURL = try #require(URL(string: "http://127.0.0.1:9/socket"))
            let socket = session.webSocketTask(with: socketURL)
            let data = session.dataTask(with: dataURL)

            let claims = (NetworkMockingURLProtocol.canInit(with: socket), NetworkMockingURLProtocol.canInit(with: data))

            #expect(claims == (false, true))
        }
    }
#endif
