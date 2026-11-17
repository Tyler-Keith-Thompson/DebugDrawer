#if DEBUG
    @testable import DebugDrawerNetworkPlugin
    import Foundation
    import Network
    import os
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

    // MARK: - Recording loopback server

    /// Answers every request with one small HTTP/1.1 200 response, keeping each request it read:
    /// its request line, headers (names lowercased) and body.
    private final class RecordingServer: Sendable {
        struct Request: Sendable {
            var requestLine: String
            var headers: [String: String]
            var body: Data
        }

        private let listener: NWListener
        private let queue = DispatchQueue(label: "RecordingServer")
        private let received = OSAllocatedUnfairLock<[Request]>(initialState: [])

        init() throws {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
            listener = try NWListener(using: parameters)
        }

        /// The requests read, in order. The response is sent after the request is kept, so a
        /// client that has its response finds its request here.
        var requests: [Request] {
            received.withLock { $0 }
        }

        func start() async throws -> UInt16 {
            listener.newConnectionHandler = { [queue, received] connection in
                connection.start(queue: queue)
                Self.read(connection, buffer: Data()) { request in
                    received.withLock { $0.append(request) }
                    let body = #"{"ok":true}"#
                    let response = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n"
                        + "Content-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
                    connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
                        connection.cancel()
                    })
                }
            }
            return try await withCheckedThrowingContinuation { continuation in
                let resumed = OSAllocatedUnfairLock(initialState: false)
                listener.stateUpdateHandler = { [listener] state in
                    let claim = { resumed.withLock { wasResumed in
                        defer { wasResumed = true }
                        return !wasResumed
                    } }
                    switch state {
                    case .ready:
                        if let port = listener.port?.rawValue, claim() { continuation.resume(returning: port) }
                    case let .failed(error):
                        if claim() { continuation.resume(throwing: error) }
                    default:
                        break
                    }
                }
                listener.start(queue: queue)
            }
        }

        func stop() {
            listener.cancel()
        }

        /// Reads until the headers and as many body bytes as `Content-Length` says have arrived.
        private static func read(_ connection: NWConnection, buffer: Data, completion: @escaping @Sendable (Request) -> Void) {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { chunk, _, isComplete, error in
                var buffer = buffer
                if let chunk { buffer.append(chunk) }
                if let request = parse(buffer) {
                    completion(request)
                } else if !isComplete, error == nil {
                    read(connection, buffer: buffer, completion: completion)
                }
            }
        }

        private static func parse(_ data: Data) -> Request? {
            guard let end = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
            let head = (String(bytes: data[..<end.lowerBound], encoding: .utf8) ?? "").components(separatedBy: "\r\n")
            var headers: [String: String] = [:]
            for line in head.dropFirst() {
                guard let colon = line.firstIndex(of: ":") else { continue }
                headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
            let length = Int(headers["content-length"] ?? "0") ?? 0
            let body = data[end.upperBound...]
            guard body.count >= length else { return nil }
            return Request(requestLine: head.first ?? "", headers: headers, body: Data(body.prefix(length)))
        }
    }
#endif
