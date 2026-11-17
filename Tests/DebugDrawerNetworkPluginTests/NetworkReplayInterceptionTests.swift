#if DEBUG
    @testable import DebugDrawerNetworkPlugin
    import Foundation
    import Testing

    // These requests go through the URL protocol, which reads the process's one set of mock rules,
    // so they are part of the mock interception suite, which is serialized: no two of its tests
    // change the rules at once, and none of its loopback requests meets another's rules. The
    // plugin's protocol sends a request on through a session of its own, so the request reaches a
    // loopback server, which keeps what arrived; the replays go through the production sender over
    // a session with the protocol registered, as `installNetwork()` gives every session.
    extension NetworkMockInterceptionTests {
        @Test("Resending a captured GET logs a new entry with the server's answer, marked as a replay of the original")
        func resendsCapturedGet() async throws {
            let server = try RecordingServer()
            defer { server.stop() }
            let port = try await server.start()
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [DebugNetworkProtocol.self]
            let session = URLSession(configuration: configuration)
            let address = "http://127.0.0.1:\(port)/v1/greeting?attempt=\(UUID().uuidString)"
            let url = try #require(URL(string: address))
            let logged = NetworkStore.shared.$entries.values
            _ = try await session.data(from: url)
            var captured: NetworkEntry?
            for await entries in logged {
                if let match = entries.first(where: { $0.url == address && $0.isComplete && $0.replayOf == nil }) {
                    captured = match
                    break
                }
            }
            let original = try #require(captured)
            let sut = NetworkReplayModel(sender: _NetworkReplaySender(session: session))

            await sut.resend(original)

            var replayed: NetworkEntry?
            for await entries in NetworkStore.shared.$entries.values {
                if let match = entries.first(where: { $0.replayOf == original.id && $0.isComplete }) {
                    replayed = match
                    break
                }
            }
            let actual = try #require(replayed)
            #expect(actual.id != original.id)
            #expect(actual.method == "GET")
            #expect(actual.url == address)
            #expect(actual.statusCode == 200)
            #expect(actual.responseBody == Data(#"{"ok":true}"#.utf8))
            #expect(server.requests.map(\.requestLine) == Array(repeating: "GET /v1/greeting?\(url.query() ?? "") HTTP/1.1", count: 2))
            #expect(sut.statuses.isEmpty)
        }

        @Test("An edited URL and header reach the server as edited")
        func editedURLAndHeaderArrive() async throws {
            let server = try RecordingServer()
            defer { server.stop() }
            let port = try await server.start()
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [DebugNetworkProtocol.self]
            let session = URLSession(configuration: configuration)
            let original = NetworkEntry(
                timestamp: Date(), method: "GET", url: "http://127.0.0.1:\(port)/v1/users/1", host: "127.0.0.1", path: "/v1/users/1",
                requestHeaders: ["Accept": "application/json", "X-Client": "app"], requestBody: nil, statusCode: 200, isComplete: true
            )
            var draft = NetworkReplayDraft(original)
            draft.url = "http://127.0.0.1:\(port)/v1/users/2?view=full"
            let client = try #require(draft.headers.firstIndex { $0.name == "X-Client" })
            draft.headers[client].value = "drawer"
            let request = try #require(draft.request)
            let sut = NetworkReplayModel(sender: _NetworkReplaySender(session: session))

            await sut.resend(request, replaying: original.id)

            let arrived = try #require(server.requests.first)
            #expect(server.requests.count == 1)
            #expect(arrived.requestLine == "GET /v1/users/2?view=full HTTP/1.1")
            #expect(arrived.headers["x-client"] == "drawer")
            #expect(arrived.headers["accept"] == "application/json")
        }

        @Test("An edited method and body reach the server as edited")
        func editedMethodAndBodyArrive() async throws {
            let server = try RecordingServer()
            defer { server.stop() }
            let port = try await server.start()
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [DebugNetworkProtocol.self]
            let session = URLSession(configuration: configuration)
            let original = NetworkEntry(
                timestamp: Date(), method: "POST", url: "http://127.0.0.1:\(port)/v1/orders", host: "127.0.0.1", path: "/v1/orders",
                requestHeaders: ["Content-Type": "application/json"], requestBody: Data(#"{"item":"tea"}"#.utf8),
                statusCode: 201, isComplete: true
            )
            var draft = NetworkReplayDraft(original)
            draft.method = "PUT"
            draft.body = .text(#"{"item":"coffee","quantity":2}"#)
            let request = try #require(draft.request)
            let sut = NetworkReplayModel(sender: _NetworkReplaySender(session: session))

            await sut.resend(request, replaying: original.id)

            let arrived = try #require(server.requests.first)
            #expect(arrived.requestLine == "PUT /v1/orders HTTP/1.1")
            #expect(arrived.headers["content-type"] == "application/json")
            #expect(arrived.body == Data(#"{"item":"coffee","quantity":2}"#.utf8))
        }

        @Test("The replay mark never reaches the server: a resend arrives with the original's headers and no others")
        func markStaysInProcess() async throws {
            let server = try RecordingServer()
            defer { server.stop() }
            let port = try await server.start()
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [DebugNetworkProtocol.self]
            let session = URLSession(configuration: configuration)
            let url = try #require(URL(string: "http://127.0.0.1:\(port)/mark"))
            var request = URLRequest(url: url)
            request.setValue("one", forHTTPHeaderField: "X-Debug-Test")
            _ = try await session.data(for: request)
            let original = NetworkEntry(
                timestamp: Date(), method: "GET", url: url.absoluteString, host: "127.0.0.1", path: "/mark",
                requestHeaders: ["X-Debug-Test": "one"], requestBody: nil, statusCode: 200, isComplete: true
            )
            let sut = NetworkReplayModel(sender: _NetworkReplaySender(session: session))

            await sut.resend(original)

            let arrivals = server.requests
            try #require(arrivals.count == 2)
            let expectedNames = arrivals[0].headers.keys.sorted()
            let actualNames = arrivals[1].headers.keys.sorted()
            #expect(actualNames == expectedNames)
            #expect(!arrivals[1].headers.keys.contains { $0.contains("replay") || $0.contains("debugdrawer") })
            #expect(!arrivals[1].headers.values.contains(original.id.uuidString))
        }

        @Test("A replay a mock rule matches is answered by the mock, and logged as both Mocked and Replay")
        func replayThroughMock() async throws {
            let rule = NetworkMockRule(
                name: "Orders", matcher: .init(methods: ["POST"], host: .exact("replay.invalid"), path: .exact("/v1/orders")),
                response: .init(status: 201, body: .text(#"{"id":7}"#), contentType: "application/json")
            )
            NetworkMockRules.shared.activate([rule]) { _ in nil }
            defer { NetworkMockRules.shared.activate([]) { _ in nil } }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [DebugNetworkProtocol.self]
            let session = URLSession(configuration: configuration)
            let original = NetworkEntry(
                timestamp: Date(), method: "POST", url: "https://replay.invalid/v1/orders", host: "replay.invalid", path: "/v1/orders",
                requestHeaders: ["Content-Type": "application/json"], requestBody: Data(#"{"item":"tea"}"#.utf8), isComplete: true
            )
            let sut = NetworkReplayModel(sender: _NetworkReplaySender(session: session))

            await sut.resend(original)

            var replayed: NetworkEntry?
            for await entries in NetworkStore.shared.$entries.values {
                if let match = entries.first(where: { $0.replayOf == original.id }) {
                    replayed = match
                    break
                }
            }
            let actual = try #require(replayed)
            #expect(actual.mockRuleName == "Orders")
            #expect(actual.statusCode == 201)
            #expect(actual.responseBody == Data(#"{"id":7}"#.utf8))
            #expect(actual.requestBody == Data(#"{"item":"tea"}"#.utf8))
            #expect(sut.statuses.isEmpty)
        }

        @Test("A resend that gets no answer says why on its original, and its own entry is logged failed, marked as a replay")
        func failedResend() async throws {
            // A listener stopped at once leaves its port closed, so the connection is refused.
            let server = try RecordingServer()
            let port = try await server.start()
            server.stop()
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [DebugNetworkProtocol.self]
            let session = URLSession(configuration: configuration)
            let original = NetworkEntry(
                timestamp: Date(), method: "GET", url: "http://127.0.0.1:\(port)/closed/\(UUID().uuidString)", host: "127.0.0.1",
                path: "/closed", requestHeaders: [:], requestBody: nil, statusCode: 200, isComplete: true
            )
            let sut = NetworkReplayModel(sender: _NetworkReplaySender(session: session))

            await sut.resend(original)

            var replayed: NetworkEntry?
            for await entries in NetworkStore.shared.$entries.values {
                if let match = entries.first(where: { $0.replayOf == original.id && $0.isComplete }) {
                    replayed = match
                    break
                }
            }
            let actual = try #require(replayed)
            guard case let .failed(message) = sut.statuses[original.id] else {
                Issue.record("Expected a failed status, got \(String(describing: sut.statuses[original.id]))")
                return
            }
            #expect(!message.isEmpty)
            #expect(actual.error != nil)
            #expect(actual.isFailure)
        }
    }
#endif
