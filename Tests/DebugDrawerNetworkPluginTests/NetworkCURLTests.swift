#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerNetworkPlugin
    import Foundation
    import Testing

    @Suite
    struct NetworkCURLTests {
        @Test("Copy cURL masks a configured Authorization header and keeps the others")
        func authorizationMasked() {
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSinceReferenceDate: 0), method: "GET",
                url: "https://api.example.com/v1/me", host: "api.example.com", path: "/v1/me",
                requestHeaders: ["Authorization": "Bearer s3cr3t", "Accept": "application/json"], requestBody: nil,
                isComplete: false
            )
            let redaction = DebugDrawerRedaction(headers: ["Authorization"])
            let expected = """
            curl \\
              'https://api.example.com/v1/me' \\
              -H 'Accept: application/json' \\
              -H 'Authorization: [REDACTED]'
            """

            let actual = entry.curl(redaction: redaction)

            #expect(actual == expected)
            #expect(!actual.contains("s3cr3t"))
        }

        @Test("Copy cURL masks sensitive query items and JSON body values")
        func queryAndBodyMasked() {
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSinceReferenceDate: 0), method: "POST",
                url: "https://api.example.com/login?api_key=k1", host: "api.example.com", path: "/login",
                requestHeaders: [:], requestBody: Data(#"{"user":"ada","password":"hunter2"}"#.utf8),
                isComplete: false
            )
            let expected = """
            curl \\
              -X POST \\
              'https://api.example.com/login?api_key=%5BREDACTED%5D' \\
              -d '{"password":"[REDACTED]","user":"ada"}'
            """

            let actual = entry.curl(redaction: .standard)

            #expect(actual == expected)
        }

        @Test("With no rules, Copy cURL carries every value as sent, quotes escaped")
        func noRules() {
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSinceReferenceDate: 0), method: "PUT",
                url: "https://api.example.com/notes", host: "api.example.com", path: "/notes",
                requestHeaders: ["Authorization": "Bearer abc"], requestBody: Data("it's".utf8),
                isComplete: false
            )
            let expected = """
            curl \\
              -X PUT \\
              'https://api.example.com/notes' \\
              -H 'Authorization: Bearer abc' \\
              -d 'it'\\''s'
            """

            let actual = entry.curl(redaction: .none)

            #expect(actual == expected)
        }
    }
#endif
