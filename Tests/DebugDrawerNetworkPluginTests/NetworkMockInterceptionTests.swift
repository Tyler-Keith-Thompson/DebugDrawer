#if DEBUG
    @testable import DebugDrawerNetworkPlugin
    import Foundation
    import Testing

    // The URL protocol answers from the process's one set of rules, so these tests take turns.
    // Their requests go through a session of their own with the protocol registered, as an app's
    // sessions get it once `installNetwork()` swizzles their configuration.
    @MainActor
    @Suite(.serialized, .timeLimit(.minutes(1)))
    struct NetworkMockInterceptionTests {
        @Test("A request a rule matches gets the rule's status, headers and body, and no request is made")
        func interceptsMatchingRequest() async throws {
            let rule = NetworkMockRule(
                name: "Greeting",
                matcher: .init(methods: ["GET"], host: .exact("mock.invalid"), path: .wildcard("/v1/greeting/*")),
                response: .init(status: 201, headers: ["X-Mock": "yes"], body: .text(#"{"message":"Hello"}"#), contentType: "application/json")
            )
            NetworkMockRules.shared.activate([rule]) { _ in nil }
            defer { NetworkMockRules.shared.activate([]) { _ in nil } }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [DebugNetworkProtocol.self]
            let session = URLSession(configuration: configuration)
            // `.invalid` never resolves, so a request that reached the network would fail.
            let url = try #require(URL(string: "https://mock.invalid/v1/greeting/\(UUID().uuidString)"))
            let expectedBody = Data(#"{"message":"Hello"}"#.utf8)

            let (data, response) = try await session.data(from: url)

            let http = try #require(response as? HTTPURLResponse)
            #expect(http.statusCode == 201)
            #expect(http.value(forHTTPHeaderField: "X-Mock") == "yes")
            #expect(http.value(forHTTPHeaderField: "Content-Type") == "application/json")
            #expect(http.value(forHTTPHeaderField: "Content-Length") == String(expectedBody.count))
            #expect(http.url == url)
            #expect(data == expectedBody)
        }

        @Test("A mocked request is logged complete, marked with the rule's name, and with no network timing")
        func marksLogEntry() async throws {
            let rule = NetworkMockRule(
                name: "Orders down", matcher: .init(host: .exact("mock.invalid"), path: .exact("/orders")), response: .init(status: 503)
            )
            NetworkMockRules.shared.activate([rule]) { _ in nil }
            defer { NetworkMockRules.shared.activate([]) { _ in nil } }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [DebugNetworkProtocol.self]
            let session = URLSession(configuration: configuration)
            let address = "https://mock.invalid/orders?attempt=\(UUID().uuidString)"
            let url = try #require(URL(string: address))
            let logged = NetworkStore.shared.$entries.values

            _ = try await session.data(from: url)

            var entry: NetworkEntry?
            for await entries in logged {
                if let match = entries.first(where: { $0.url == address }) {
                    entry = match
                    break
                }
            }
            let actual = try #require(entry)
            #expect(actual.mockRuleName == "Orders down")
            #expect(actual.isComplete)
            #expect(actual.statusCode == 503)
            #expect(actual.metrics == nil)
            #expect(actual.isFailure)
        }

        @Test("A request no rule matches reaches the server unchanged: its method, URL, headers and body")
        func passesThroughUnmatched() async throws {
            let server = try RecordingServer()
            defer { server.stop() }
            let port = try await server.start()
            // Rules for the same host on another path, and for another host on the same path.
            let rules = [
                NetworkMockRule(
                    name: "Other path", matcher: .init(host: .exact("127.0.0.1"), path: .exact("/elsewhere")), response: .init(status: 500)
                ),
                NetworkMockRule(
                    name: "Other host", matcher: .init(host: .exact("mock.invalid"), path: .exact("/echo")), response: .init(status: 500)
                ),
                NetworkMockRule(name: "Other method", matcher: .init(methods: ["GET"], host: .exact("127.0.0.1")), response: .init(status: 500))
            ]
            NetworkMockRules.shared.activate(rules) { _ in nil }
            defer { NetworkMockRules.shared.activate([]) { _ in nil } }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [DebugNetworkProtocol.self]
            let session = URLSession(configuration: configuration)
            let url = try #require(URL(string: "http://127.0.0.1:\(port)/echo?name=Ada&n=1"))
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("pass-through", forHTTPHeaderField: "X-Debug-Test")
            request.httpBody = Data(#"{"hello":"server"}"#.utf8)

            let (data, response) = try await session.data(for: request)

            let arrived = try #require(server.requests.first)
            #expect(arrived.requestLine == "POST /echo?name=Ada&n=1 HTTP/1.1")
            #expect(arrived.headers["x-debug-test"] == "pass-through")
            #expect(arrived.headers["content-type"] == "application/json")
            #expect(arrived.body == Data(#"{"hello":"server"}"#.utf8))
            #expect((response as? HTTPURLResponse)?.statusCode == 200)
            #expect(data == Data(#"{"ok":true}"#.utf8))
        }
    }
#endif
