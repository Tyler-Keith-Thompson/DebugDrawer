#if DEBUG
    @testable import DebugDrawerNetworkPlugin
    import DebugDrawer
    import Foundation
    import Testing

    @Suite
    struct NetworkReplayReportTests {
        @Test("The HTTP Archive's comment names the request a replay resent, by method, redacted URL and start, before the mock that answered it")
        func archiveComment() {
            let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
            let original = NetworkEntry(
                timestamp: start, method: "POST", url: "https://api.example.com/v1/orders?token=secret", host: "api.example.com",
                path: "/v1/orders", requestHeaders: [:], requestBody: nil, statusCode: 201, duration: 0.2, isComplete: true
            )
            let replay = NetworkEntry(
                timestamp: start + 10, method: "POST", url: "https://api.example.com/v1/orders", host: "api.example.com",
                path: "/v1/orders", requestHeaders: [:], requestBody: nil, statusCode: 201, duration: 0.1, isComplete: true,
                mockRuleName: "Orders", replayOf: original.id
            )
            let orphan = NetworkEntry(
                timestamp: start + 20, method: "GET", url: "https://api.example.com/v1/gone", host: "api.example.com",
                path: "/v1/gone", requestHeaders: [:], requestBody: nil, statusCode: 200, duration: 0.1, isComplete: true, replayOf: UUID()
            )
            // The URL as the archive masks it: the token's value is redacted.
            let maskedURL = DebugDrawerRedaction.standard.redacting(url: original.url)
            let expected = [
                nil,
                "Replay of the POST \(maskedURL) started 2026-05-09T06:13:20.000Z. Answered by the network mock “Orders”",
                "Replay of a request not in this archive"
            ]

            let actual = HTTPArchive([orphan, replay, original], redaction: .standard).log.entries.map(\.comment)

            #expect(actual == expected)
            #expect(!maskedURL.contains("secret"))
        }
    }
#endif
