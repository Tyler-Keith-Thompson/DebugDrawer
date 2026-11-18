#if DEBUG
    @testable import DebugDrawerNetworkPlugin
    import Foundation
    import Testing

    // These requests go through the URL protocol, which reads the process's one set of mock rules,
    // so they are part of the mock interception suite, which is serialized. The protocol sends each
    // request on through its own session to a loopback server, which keeps the body that arrived.
    extension NetworkMockInterceptionTests {
        @Test("A request whose body is a stream reaches the server with every byte of it, and the log records those bytes")
        func forwardsStreamBody() async throws {
            let server = try RecordingServer()
            defer { server.stop() }
            let port = try await server.start()
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [DebugNetworkProtocol.self]
            let session = URLSession(configuration: configuration)
            let address = "http://127.0.0.1:\(port)/v1/upload?attempt=\(UUID().uuidString)"
            let url = try #require(URL(string: address))
            let expected = Data(#"{"name":"tea","quantity":2}"#.utf8)
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBodyStream = InputStream(data: expected)
            let logged = NetworkStore.shared.$entries.values

            _ = try await session.data(for: request)

            var captured: NetworkEntry?
            for await entries in logged {
                if let match = entries.first(where: { $0.url == address && $0.isComplete }) {
                    captured = match
                    break
                }
            }
            let entry = try #require(captured)
            let arrived = try #require(server.requests.first)
            #expect(arrived.requestLine == "POST /v1/upload?\(url.query() ?? "") HTTP/1.1")
            #expect(arrived.body == expected)
            #expect(entry.requestBody == expected)
            #expect(entry.requestBodySize == expected.count)
            #expect(!entry.isRequestBodyTruncated)
        }

        @Test("A request whose body is data reaches the server with that body, and the log records it")
        func forwardsDataBody() async throws {
            let server = try RecordingServer()
            defer { server.stop() }
            let port = try await server.start()
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [DebugNetworkProtocol.self]
            let session = URLSession(configuration: configuration)
            let address = "http://127.0.0.1:\(port)/v1/orders?attempt=\(UUID().uuidString)"
            let url = try #require(URL(string: address))
            let expected = Data(#"{"item":"coffee"}"#.utf8)
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = expected
            let logged = NetworkStore.shared.$entries.values

            _ = try await session.data(for: request)

            var captured: NetworkEntry?
            for await entries in logged {
                if let match = entries.first(where: { $0.url == address && $0.isComplete }) {
                    captured = match
                    break
                }
            }
            let entry = try #require(captured)
            let arrived = try #require(server.requests.first)
            #expect(arrived.body == expected)
            #expect(arrived.headers["content-length"] == String(expected.count))
            #expect(entry.requestBody == expected)
            #expect(!entry.isRequestBodyTruncated)
        }

        @Test("A request whose body is an empty stream reaches the server with an empty body, and the log records no body")
        func forwardsEmptyStream() async throws {
            let server = try RecordingServer()
            defer { server.stop() }
            let port = try await server.start()
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [DebugNetworkProtocol.self]
            let session = URLSession(configuration: configuration)
            let address = "http://127.0.0.1:\(port)/v1/empty?attempt=\(UUID().uuidString)"
            let url = try #require(URL(string: address))
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBodyStream = InputStream(data: Data())
            let logged = NetworkStore.shared.$entries.values

            let (_, response) = try await session.data(for: request)

            var captured: NetworkEntry?
            for await entries in logged {
                if let match = entries.first(where: { $0.url == address && $0.isComplete }) {
                    captured = match
                    break
                }
            }
            let entry = try #require(captured)
            let arrived = try #require(server.requests.first)
            #expect((response as? HTTPURLResponse)?.statusCode == 200)
            #expect(arrived.requestLine == "POST /v1/empty?\(url.query() ?? "") HTTP/1.1")
            #expect(arrived.body.isEmpty)
            #expect(entry.requestBody == nil)
            #expect(entry.requestBodySize == nil)
        }
    }
#endif
