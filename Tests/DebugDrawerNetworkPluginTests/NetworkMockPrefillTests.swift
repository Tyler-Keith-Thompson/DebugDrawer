#if DEBUG
    @testable import DebugDrawerNetworkPlugin
    import Foundation
    import Testing

    @MainActor
    @Suite
    struct NetworkMockPrefillTests {
        @Test("Mock This matches the request's method, host and exact path, and answers with its status, headers and body")
        func prefill() throws {
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000), method: "POST",
                url: "https://api.example.com/v1/orders/?draft=1", host: "api.example.com", path: "/v1/orders",
                requestHeaders: [:], requestBody: nil, statusCode: 422,
                responseHeaders: ["Content-Type": "application/json", "Content-Length": "17", "Content-Encoding": "gzip", "X-Request-Id": "abc"],
                responseBody: Data(#"{"error":"nope"}"#.utf8), duration: 0.2, isComplete: true
            )
            let expectedMatcher = NetworkMockRule.Matcher(methods: ["POST"], host: .exact("api.example.com"), path: .exact("/v1/orders/"))
            let expectedResponse = NetworkMockRule.Response(
                status: 422, headers: ["Content-Type": "application/json", "X-Request-Id": "abc"], body: .text(#"{"error":"nope"}"#)
            )

            let actual = NetworkMockRule(mocking: entry)

            #expect(actual.name == "POST /v1/orders/")
            #expect(actual.isEnabled)
            #expect(actual.matcher == expectedMatcher)
            #expect(actual.response == expectedResponse)
        }

        @Test("A request that never got an answer is mocked as 200 with no body")
        func failedRequest() {
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000), method: "GET",
                url: "https://api.example.com/v1/users", host: "api.example.com", path: "/v1/users",
                requestHeaders: [:], requestBody: nil, error: "The network connection was lost.", isComplete: true
            )
            let expected = NetworkMockRule.Response(status: 200, headers: [:], body: .empty)

            let actual = NetworkMockRule(mocking: entry).response

            #expect(actual == expected)
        }

        @Test("A body that isn't text is kept as a file in the storage, and the rule sends it")
        func binaryBody() {
            let storage = FakeNetworkMockStorage()
            let sut = NetworkMocksModel(storage: storage, active: NetworkMockRules())
            let bytes = Data([0xFF, 0xD8, 0xFF, 0x00])
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000), method: "GET",
                url: "https://cdn.test/photo", host: "cdn.test", path: "/photo",
                requestHeaders: [:], requestBody: nil, statusCode: 200, responseHeaders: ["Content-Type": "image/jpeg"],
                responseBody: bytes, isComplete: true
            )

            let actual = sut.rule(mocking: entry)

            guard case let .file(name) = actual.response.body else {
                Issue.record("The body is \(actual.response.body), not a file")
                return
            }
            #expect(storage.body(named: name) == bytes)
            #expect(actual.response.headers == ["Content-Type": "image/jpeg"])
        }

        @Test("A rule made with Mock This and saved answers the same request, and persists")
        func mockThisThenSave() throws {
            let storage = FakeNetworkMockStorage()
            let active = NetworkMockRules()
            let sut = NetworkMocksModel(storage: storage, active: active)
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000), method: "GET",
                url: "https://example.com/", host: "example.com", path: "/",
                requestHeaders: [:], requestBody: nil, statusCode: 200, responseHeaders: ["Content-Type": "text/html"],
                responseBody: Data("<html>Example</html>".utf8), isComplete: true
            )
            let url = try #require(URL(string: entry.url))

            sut.save(sut.rule(mocking: entry))
            let relaunch = NetworkMocksModel(storage: storage, active: NetworkMockRules())
            relaunch.load()

            #expect(active.answer(method: "GET", url: url)?.body == Data("<html>Example</html>".utf8))
            #expect(relaunch.rules.map(\.name) == ["GET /"])
        }
    }
#endif
