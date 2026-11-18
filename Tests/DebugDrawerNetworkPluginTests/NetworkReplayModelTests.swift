#if DEBUG
    @testable import DebugDrawerNetworkPlugin
    import Foundation
    import Testing

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct NetworkReplayModelTests {
        @Test("Resend sends the captured request unchanged, marked as a replay of it")
        func resendMarks() async throws {
            let entry = NetworkEntry(
                timestamp: Date(), method: "GET", url: "https://api.example.com/v1/greeting", host: "api.example.com",
                path: "/v1/greeting", requestHeaders: ["Accept": "application/json"], requestBody: nil, statusCode: 200, isComplete: true
            )
            let sender = FakeNetworkReplaySender()
            let sut = NetworkReplayModel(sender: sender)

            await sut.resend(entry)

            let actual = try #require(sender.sent.first)
            #expect(sender.sent.count == 1)
            #expect(actual.replayOf == entry.id)
            #expect(actual.httpMethod == "GET")
            #expect(actual.url?.absoluteString == "https://api.example.com/v1/greeting")
            #expect(actual.allHTTPHeaderFields == ["Accept": "application/json"])
            #expect(sut.statuses.isEmpty)
        }

        @Test("While a resend waits for its answer its original shows Sending; once answered, nothing")
        func sendingStatus() async throws {
            let original = UUID()
            let sender = FakeNetworkReplaySender(gated: true)
            let sut = NetworkReplayModel(sender: sender)
            let request = try URLRequest(url: #require(URL(string: "https://example.com/replay")))

            let resend = Task { await sut.resend(request, replaying: original) }
            await sender.waitUntilSent(1)
            let during = sut.statuses[original]
            sender.open()
            await resend.value

            #expect(during == .sending)
            #expect(sut.statuses[original] == nil)
        }

        @Test("A resend that gets no answer shows why on its original")
        func failure() async throws {
            let original = UUID()
            let sender = FakeNetworkReplaySender(failure: URLError(.notConnectedToInternet))
            let sut = NetworkReplayModel(sender: sender)
            let request = try URLRequest(url: #require(URL(string: "https://example.com/replay")))
            let expected = NetworkReplayStatus.failed(URLError(.notConnectedToInternet).localizedDescription)

            await sut.resend(request, replaying: original)

            #expect(sut.statuses[original] == expected)
        }

        @Test("A cancelled resend isn't a failure: it leaves no status")
        func cancelled() async throws {
            let original = UUID()
            let sender = FakeNetworkReplaySender(failure: URLError(.cancelled))
            let sut = NetworkReplayModel(sender: sender)
            let request = try URLRequest(url: #require(URL(string: "https://example.com/replay")))

            await sut.resend(request, replaying: original)

            #expect(sut.statuses.isEmpty)
        }

        @Test("The links: a replay names its original; a resent request lists its replays, newest first")
        func links() {
            let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
            let original = NetworkEntry(
                timestamp: start, method: "GET", url: "https://example.com/", host: "example.com", path: "/",
                requestHeaders: [:], requestBody: nil, isComplete: true
            )
            let first = NetworkEntry(
                timestamp: start + 1, method: "GET", url: "https://example.com/", host: "example.com", path: "/",
                requestHeaders: [:], requestBody: nil, isComplete: true, replayOf: original.id
            )
            let second = NetworkEntry(
                timestamp: start + 2, method: "GET", url: "https://example.com/", host: "example.com", path: "/",
                requestHeaders: [:], requestBody: nil, isComplete: true, replayOf: original.id
            )
            let orphan = NetworkEntry(
                timestamp: start + 3, method: "GET", url: "https://example.com/", host: "example.com", path: "/",
                requestHeaders: [:], requestBody: nil, isComplete: true, replayOf: UUID()
            )
            let entries = [orphan, second, first, original]

            let ofOriginal = NetworkReplayLinks(of: original, in: entries)
            let ofFirst = NetworkReplayLinks(of: first, in: entries)
            let ofOrphan = NetworkReplayLinks(of: orphan, in: entries)

            #expect(ofOriginal.original == nil)
            #expect(ofOriginal.replays == [second.id, first.id])
            #expect(ofFirst.original?.id == original.id)
            #expect(ofFirst.replays.isEmpty)
            #expect(ofOrphan.original == nil)
        }

        @Test("Resend of a request whose body the log cut short sends nothing, and its status says the body was cut")
        func truncatedBodyNotSent() async {
            let entry = NetworkEntry(
                timestamp: Date(), method: "POST", url: "https://api.example.com/v1/upload", host: "api.example.com",
                path: "/v1/upload", requestHeaders: [:], requestBody: Data(repeating: 0x61, count: 1024), requestBodySize: 4096,
                statusCode: 201, isComplete: true
            )
            let sender = FakeNetworkReplaySender()
            let sut = NetworkReplayModel(sender: sender)
            let expected = NetworkReplayStatus.failed(
                "The log kept only the first 1 KB of its 4 KB body. Use Edit and Resend to replace or remove the body."
            )

            await sut.resend(entry)

            #expect(sender.sent.isEmpty)
            #expect(sut.statuses[entry.id] == expected)
        }

        @Test("Resend of a request whose body is within the body limit sends the body unchanged")
        func wholeBodySent() async throws {
            let body = Data(#"{"item":"tea","quantity":1}"#.utf8)
            let entry = NetworkEntry(
                timestamp: Date(), method: "POST", url: "https://api.example.com/v1/orders", host: "api.example.com",
                path: "/v1/orders", requestHeaders: ["Content-Type": "application/json"], requestBody: body,
                requestBodySize: body.count, statusCode: 201, isComplete: true
            )
            let sender = FakeNetworkReplaySender()
            let sut = NetworkReplayModel(sender: sender)

            await sut.resend(entry)

            let actual = try #require(sender.sent.first)
            #expect(sender.sent.count == 1)
            #expect(actual.httpBody == body)
            #expect(sut.statuses.isEmpty)
        }
    }
#endif
