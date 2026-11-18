#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerCookiesPlugin
    import Foundation
    import Testing

    @Suite
    struct CookiesReportTests {
        @Test("The report gets cookies.txt in Copy's format, a session cookie's value masked")
        func cookiesAsText() throws {
            let session = try #require(HTTPCookie(properties: [
                .name: "session_id", .value: "abc123", .domain: "example.com", .path: "/"
            ]))
            let theme = try #require(HTTPCookie(properties: [
                .name: "theme", .value: "dark", .domain: "example.com", .path: "/"
            ]))
            let redaction = DebugDrawerRedaction(keys: ["session"])
            let cookies = [StoredCookie(cookie: session, store: .urlSession), StoredCookie(cookie: theme, store: .urlSession)]
            let expected = cookies.report(redaction: redaction)
            var actual = DebugDrawerReport()

            CookiesPlugin.contribute(cookies, to: &actual, redaction: redaction)

            let file = try #require(actual.files.first)
            let text = try #require(String(bytes: file.data, encoding: .utf8))
            #expect(file.name == "cookies.txt")
            #expect(file.kind == .text)
            #expect(text == expected)
            #expect(text.contains("Name: session_id\nValue: [REDACTED]\n"))
            #expect(!text.contains("abc123"))
        }

        @Test("No cookies add nothing to the report")
        func noCookies() {
            var actual = DebugDrawerReport()

            CookiesPlugin.contribute([], to: &actual, redaction: .standard)

            #expect(actual.files.isEmpty)
        }
    }
#endif
