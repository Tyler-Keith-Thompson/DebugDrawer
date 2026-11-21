#if DEBUG
    @testable import DebugDrawer
    import Foundation
    import Testing

    @Suite
    struct RedactionTests {
        @Test("The standard rules mask the Authorization header whatever its case")
        func standardAuthorization() {
            let sut = DebugDrawerRedaction.standard
            let headers = ["authorization": "Bearer abc", "Accept": "application/json"]
            let expected = ["authorization": DebugDrawerRedaction.mask, "Accept": "application/json"]

            let actual = sut.redacting(headers: headers)

            #expect(actual == expected)
        }

        @Test("A header whose name contains a key pattern is masked")
        func headerMatchingKeyPattern() {
            let sut = DebugDrawerRedaction(keys: ["token"])

            let actual = sut.masksHeader("X-Refresh-Token")

            #expect(actual)
        }

        @Test("No rules mask nothing")
        func noRules() {
            let sut = DebugDrawerRedaction.none
            let headers = ["Authorization": "Bearer abc"]
            let body = Data(#"{"password":"hunter2"}"#.utf8)
            let url = "https://example.com/?token=abc"

            #expect(sut.redacting(headers: headers) == headers)
            #expect(sut.redacting(json: body) == body)
            #expect(sut.redacting(url: url) == url)
            #expect(sut.redacting("abc", forKey: "token") == "abc")
        }

        @Test("An empty key pattern matches no key")
        func emptyKeyPattern() {
            let sut = DebugDrawerRedaction(keys: [""])

            let actual = sut.masksKey("anything")

            #expect(!actual)
        }

        @Test("Key patterns match case-insensitively anywhere in the key")
        func keyPatternCase() {
            let sut = DebugDrawerRedaction(keys: ["Token"])

            #expect(sut.masksKey("accessTOKEN"))
            #expect(sut.masksKey("token"))
            #expect(!sut.masksKey("tok"))
        }

        @Test("A sensitive query item's value is masked in the URL; the others are kept")
        func urlQuery() {
            let sut = DebugDrawerRedaction(keys: ["token"])
            let url = "https://example.com/v1/users?page=2&access_token=abc"
            let expected = "https://example.com/v1/users?page=2&access_token=%5BREDACTED%5D"

            let actual = sut.redacting(url: url)

            #expect(actual == expected)
        }

        @Test("A URL without a sensitive query item comes back unchanged")
        func urlWithoutSensitiveQuery() {
            let sut = DebugDrawerRedaction.standard
            let url = "https://example.com/v1/users?page=2"

            let actual = sut.redacting(url: url)

            #expect(actual == url)
        }

        @Test("A JSON key containing a key pattern is masked at any depth, in arrays too")
        func jsonKeysAtDepth() throws {
            let sut = DebugDrawerRedaction(keys: ["password"])
            let body = Data(#"{"users":[{"name":"Ada","password":"x"}],"count":1}"#.utf8)
            let expected = #"{"count":1,"users":[{"name":"Ada","password":"[REDACTED]"}]}"#

            let actual = try #require(String(bytes: sut.redacting(json: body), encoding: .utf8))

            #expect(actual == expected)
        }

        @Test("A JSON path masks the value at that path only; * matches any key")
        func jsonPaths() throws {
            let sut = DebugDrawerRedaction(jsonPaths: ["user.ssn", "*.pin"])
            let body = Data(#"{"user":{"ssn":"123","pin":"9"},"ssn":"top","card":{"pin":"1"}}"#.utf8)
            let expected = #"{"card":{"pin":"[REDACTED]"},"ssn":"top","user":{"pin":"[REDACTED]","ssn":"[REDACTED]"}}"#

            let actual = try #require(String(bytes: sut.redacting(json: body), encoding: .utf8))

            #expect(actual == expected)
        }

        @Test("A JSON path names a whole value: an object under it is masked as one")
        func jsonPathObject() throws {
            let sut = DebugDrawerRedaction(jsonPaths: ["credentials"])
            let body = Data(#"{"credentials":{"user":"ada","key":"k"},"id":7}"#.utf8)
            let expected = #"{"credentials":"[REDACTED]","id":7}"#

            let actual = try #require(String(bytes: sut.redacting(json: body), encoding: .utf8))

            #expect(actual == expected)
        }

        @Test("A body that isn't JSON, or has nothing to mask, comes back byte for byte")
        func bodiesLeftAlone() {
            let sut = DebugDrawerRedaction.standard
            let form = Data("a=1&b=2".utf8)
            let json = Data(#"{ "b": 1, "a": 2 }"#.utf8)

            #expect(sut.redacting(json: form) == form)
            #expect(sut.redacting(json: json) == json)
            #expect(sut.redacting(json: Data()) == Data())
        }

        @Test("Adding rules keeps the existing ones")
        func adding() {
            let sut = DebugDrawerRedaction(headers: ["Authorization"])

            let actual = sut.adding(headers: ["X-Api-Signature"], keys: ["pin"], jsonPaths: ["a.b"])

            #expect(actual.headerNames == ["authorization", "x-api-signature"])
            #expect(actual.keyPatterns == ["pin"])
            #expect(actual.jsonPaths == ["a.b"])
        }

        @MainActor
        @Test("One call on the drawer adds header names, key patterns and JSON paths to its rules")
        func drawerRedact() throws {
            let suite = "RedactionTests.\(#function).\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let drawer = DebugDrawer(defaults: defaults)
            drawer.redaction = .none

            drawer.redact(headers: ["X-Session-Id"], keys: ["pin"], jsonPaths: ["user.ssn"])
            let actual = drawer.redaction

            #expect(actual == DebugDrawerRedaction(headers: ["X-Session-Id"], keys: ["pin"], jsonPaths: ["user.ssn"]))
        }

        @MainActor
        @Test("The drawer starts with the standard rules")
        func drawerDefault() throws {
            let suite = "RedactionTests.\(#function).\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let drawer = DebugDrawer(defaults: defaults)

            let actual = drawer.redaction

            #expect(actual == .standard)
        }
    }
#endif
