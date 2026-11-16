#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerCookiesPlugin
    import Foundation
    import Testing

    @Suite
    struct CookieReportTests {
        @Test("Copy masks a cookie whose name matches a key pattern and keeps the others")
        func nameMatches() throws {
            let session = try #require(HTTPCookie(properties: [
                .name: "session_id", .value: "abc123", .domain: "example.com", .path: "/"
            ]))
            let theme = try #require(HTTPCookie(properties: [
                .name: "theme", .value: "dark", .domain: "example.com", .path: "/"
            ]))
            let redaction = DebugDrawerRedaction(keys: ["session"])

            let actual = [session, theme].report(redaction: redaction)

            #expect(actual.contains("Name: session_id\nValue: [REDACTED]\n"))
            #expect(actual.contains("Name: theme\nValue: dark\n"))
            #expect(!actual.contains("abc123"))
        }

        @Test("Copy masks every cookie's value when the rules mask the Cookie header, as the standard rules do")
        func cookieHeaderMasked() throws {
            let theme = try #require(HTTPCookie(properties: [
                .name: "theme", .value: "dark", .domain: "example.com", .path: "/"
            ]))

            let actual = [theme].report(redaction: .standard)

            #expect(actual.contains("Value: [REDACTED]\n"))
            #expect(!actual.contains("dark"))
        }

        @Test("With no rules, Copy carries each cookie's value")
        func noRules() throws {
            let theme = try #require(HTTPCookie(properties: [
                .name: "theme", .value: "dark", .domain: "example.com", .path: "/"
            ]))
            let expected = """
            HTTP Cookies (1)
            ========================================

            Name: theme
            Value: dark
            Domain: example.com
            Path: /
            Secure: false

            """

            let actual = [theme].report(redaction: .none)

            #expect(actual == expected)
        }
    }
#endif
