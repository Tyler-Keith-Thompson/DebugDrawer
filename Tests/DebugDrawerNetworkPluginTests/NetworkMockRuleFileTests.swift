#if DEBUG
    @testable import DebugDrawerNetworkPlugin
    import Foundation
    import Testing

    @Suite
    struct NetworkMockRuleFileTests {
        @Test("Rules of every pattern and body kind come back from the file as they were saved")
        func roundTrip() throws {
            let rules = [
                NetworkMockRule(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID(),
                    name: "Users",
                    matcher: .init(methods: ["GET", "HEAD"], host: .wildcard("*.example.com"), path: .regex(#"/users/\d+"#), query: ["page": "2"]),
                    response: .init(status: 201, headers: ["X-Mock": "yes"], body: .text(#"{"id":1}"#), contentType: "application/json")
                ),
                NetworkMockRule(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000002") ?? UUID(),
                    name: "Avatar",
                    isEnabled: false,
                    matcher: .init(host: .exact("cdn.test"), path: .exact("/avatar.png")),
                    response: .init(status: 200, body: .file("avatar.png"))
                ),
                NetworkMockRule(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000003") ?? UUID(),
                    name: "Anything",
                    matcher: .init(),
                    response: .init(status: 503, body: .empty)
                )
            ]

            let actual = try NetworkMockRuleFile.decode(NetworkMockRuleFile.encode(rules))

            #expect(actual == rules)
        }

        @Test("The file names its format version and lists methods sorted, so saving twice writes the same bytes")
        func stableFormat() throws {
            let rule = NetworkMockRule(
                id: UUID(uuidString: "00000000-0000-0000-0000-00000000000A") ?? UUID(),
                name: "Greeting",
                matcher: .init(methods: ["POST", "GET", "DELETE"], host: .exact("api.test"), path: .wildcard("/v1/*")),
                response: .init(status: 200, body: .text("hi"))
            )
            let expected = """
            {
              "rules" : [
                {
                  "id" : "00000000-0000-0000-0000-00000000000A",
                  "isEnabled" : true,
                  "matcher" : {
                    "host" : {
                      "kind" : "exact",
                      "value" : "api.test"
                    },
                    "methods" : [
                      "DELETE",
                      "GET",
                      "POST"
                    ],
                    "path" : {
                      "kind" : "wildcard",
                      "value" : "/v1/*"
                    },
                    "query" : {

                    }
                  },
                  "name" : "Greeting",
                  "response" : {
                    "body" : {
                      "kind" : "text",
                      "text" : "hi"
                    },
                    "headers" : {

                    },
                    "status" : 200
                  }
                }
              ],
              "version" : 1
            }
            """

            let actual = String(bytes: NetworkMockRuleFile.encode([rule]), encoding: .utf8)

            #expect(actual == expected)
        }

        @Test("A file of a later format version is refused with its version")
        func laterVersion() {
            let data = Data(#"{"version": 2, "rules": [{"something": "new"}]}"#.utf8)

            #expect(throws: NetworkMockRuleFile.ReadError.unsupportedVersion(2)) {
                try NetworkMockRuleFile.decode(data)
            }
        }

        @Test("A version below 1 is refused as unsupported")
        func versionZero() {
            let data = Data(#"{"version": 0, "rules": []}"#.utf8)

            #expect(throws: NetworkMockRuleFile.ReadError.unsupportedVersion(0)) {
                try NetworkMockRuleFile.decode(data)
            }
        }

        @Test("A file that isn't JSON, has no version, or holds an unknown pattern kind is unreadable")
        func unreadable() {
            let files = [
                Data("not json".utf8),
                Data(#"{"rules": []}"#.utf8),
                Data(#"{"version": 1, "rules": [{"id": "00000000-0000-0000-0000-000000000001", "name": "x", "isEnabled": true, "#.utf8)
                    + Data(#""matcher": {"host": {"kind": "glob", "value": "x"}}, "#.utf8)
                    + Data(#""response": {"status": 200, "headers": {}, "body": {"kind": "empty"}}}]}"#.utf8)
            ]

            for data in files {
                #expect(throws: NetworkMockRuleFile.ReadError.unreadable) {
                    try NetworkMockRuleFile.decode(data)
                }
            }
        }

        @Test("A matcher saved without methods, host, path or query reads as one that matches anything")
        func missingMatcherFields() throws {
            let data = Data(#"{"version": 1, "rules": [{"id": "00000000-0000-0000-0000-000000000001", "name": "x", "isEnabled": true, "#.utf8)
                + Data(#""matcher": {}, "response": {"status": 204, "headers": {}, "body": {"kind": "empty"}}}]}"#.utf8)
            let expected = NetworkMockRule.Matcher()

            let actual = try #require(NetworkMockRuleFile.decode(data).first).matcher

            #expect(actual == expected)
        }

        @Test("An empty list round-trips")
        func empty() throws {
            let actual = try NetworkMockRuleFile.decode(NetworkMockRuleFile.encode([]))

            #expect(actual.isEmpty)
        }
    }
#endif
