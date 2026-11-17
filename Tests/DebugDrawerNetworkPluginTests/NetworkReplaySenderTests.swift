#if DEBUG
    @testable import DebugDrawerNetworkPlugin
    import Foundation
    import os
    import Testing

    @Suite(.timeLimit(.minutes(1)))
    struct NetworkReplaySenderTests {
        @Test("The sender hands the request to its session as given: the stub URL protocol receives the edited method, URL, headers and body")
        func sendsAsGiven() async throws {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [RecordingStubProtocol.self]
            let sut = _NetworkReplaySender(session: URLSession(configuration: configuration))
            let entry = NetworkEntry(
                timestamp: Date(), method: "GET", url: "https://stub.invalid/v1/users/1", host: "stub.invalid", path: "/v1/users/1",
                requestHeaders: ["Accept": "application/json"], requestBody: nil, isComplete: true
            )
            let run = UUID().uuidString
            var draft = NetworkReplayDraft(entry)
            draft.method = "PATCH"
            draft.url = "https://stub.invalid/v1/users/2?run=\(run)"
            draft.headers.append(NetworkNameValue(name: "X-Edited", value: "yes"))
            draft.body = .text(#"{"name":"Ada"}"#)
            let request = try #require(draft.request).markedAsReplay(of: entry.id)

            try await sut.send(request)

            let actual = try #require(RecordingStubProtocol.received.withLock { $0.first { $0.url.hasSuffix(run) } })
            #expect(actual.method == "PATCH")
            #expect(actual.url == "https://stub.invalid/v1/users/2?run=\(run)")
            #expect(actual.headers["Accept"] == "application/json")
            #expect(actual.headers["X-Edited"] == "yes")
            #expect(actual.body == Data(#"{"name":"Ada"}"#.utf8))
            #expect(actual.replayOf == entry.id)
            #expect(!actual.headers.keys.contains { $0.lowercased().contains("replay") })
        }

        @Test("A transport failure is thrown; an error status is an answer, not a throw")
        func failures() async throws {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [RecordingStubProtocol.self]
            let sut = _NetworkReplaySender(session: URLSession(configuration: configuration))
            let failing = try URLRequest(url: #require(URL(string: "https://stub.invalid/fail")))
            let serverError = try URLRequest(url: #require(URL(string: "https://stub.invalid/500")))

            await #expect(throws: URLError.self) { try await sut.send(failing) }
            try await sut.send(serverError)
        }

        @Test("The production session puts the plugin's URL protocol first, so a replay is captured")
        func interceptedSession() throws {
            let session = _NetworkReplaySender.interceptedSession()

            let classes = session.configuration.protocolClasses ?? []

            let isFirst = classes.first.map { $0 == DebugNetworkProtocol.self } ?? false
            let count = classes.count { $0 == DebugNetworkProtocol.self }

            #expect(isFirst)
            #expect(count == 1)
        }
    }

    /// Answers every request to `stub.invalid` itself and keeps what it received: 200 with no
    /// body, a 500 for the path `/500`, and no connection for `/fail`.
    private final class RecordingStubProtocol: URLProtocol, @unchecked Sendable {
        struct Received: Sendable {
            var method: String
            var url: String
            var headers: [String: String]
            var body: Data?
            var replayOf: UUID?
        }

        static let received = OSAllocatedUnfairLock<[Received]>(initialState: [])

        override static func canInit(with request: URLRequest) -> Bool {
            request.url?.host == "stub.invalid"
        }

        override static func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }

        override func startLoading() {
            guard let url = request.url else { return }
            Self.received.withLock {
                $0.append(Received(
                    method: request.httpMethod ?? "", url: url.absoluteString, headers: request.allHTTPHeaderFields ?? [:],
                    body: request.httpBody ?? request.httpBodyStream.map(Self.read), replayOf: request.replayOf
                ))
            }
            if url.path == "/fail" {
                client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
                return
            }
            let status = url.path == "/500" ? 500 : 200
            if let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil) {
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            }
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}

        private static func read(_ stream: InputStream) -> Data {
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                data.append(buffer, count: count)
            }
            return data
        }
    }
#endif
