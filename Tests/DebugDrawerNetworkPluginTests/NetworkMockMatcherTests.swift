#if DEBUG
    @testable import DebugDrawerNetworkPlugin
    import Foundation
    import Testing

    @Suite
    struct NetworkMockMatcherTests {
        @Test("An empty matcher matches every request")
        func emptyMatchesAll() throws {
            let sut = try CompiledNetworkMockMatcher(NetworkMockRule.Matcher())
            let url = try #require(URL(string: "https://anything.test/a/b?c=d"))

            let actual = sut.matches(method: "PATCH", url: url)

            #expect(actual)
        }

        @Test("Methods match any of the set, whatever their case; an empty set matches any method")
        func methods() throws {
            let sut = try CompiledNetworkMockMatcher(NetworkMockRule.Matcher(methods: ["get", "POST"]))
            let url = try #require(URL(string: "https://api.test/"))
            let expected = [true, true, true, false, false]

            let actual = ["GET", "post", "Post", "PUT", "DELETE"].map { sut.matches(method: $0, url: url) }

            #expect(actual == expected)
        }

        @Test("An exact host matches without regard to case and nothing else")
        func exactHost() throws {
            let sut = try CompiledNetworkMockMatcher(NetworkMockRule.Matcher(host: .exact("api.example.com")))
            let hosts = ["https://api.example.com/", "https://API.Example.COM/", "https://example.com/", "https://api.example.com.evil.test/"]
            let expected = [true, true, false, false]

            let actual = try hosts.map { try sut.matches(method: "GET", url: #require(URL(string: $0))) }

            #expect(actual == expected)
        }

        @Test("In a host wildcard * matches within one label and ** across labels, never the bare domain")
        func hostWildcard() throws {
            let oneLabel = try CompiledNetworkMockMatcher(NetworkMockRule.Matcher(host: .wildcard("*.example.com")))
            let anyLabels = try CompiledNetworkMockMatcher(NetworkMockRule.Matcher(host: .wildcard("**.example.com")))
            let hosts = ["https://api.example.com/", "https://a.b.example.com/", "https://example.com/", "https://api.example.org/"]
            let expectedOne = [true, false, false, false]
            let expectedAny = [true, true, false, false]

            let actualOne = try hosts.map { try oneLabel.matches(method: "GET", url: #require(URL(string: $0))) }
            let actualAny = try hosts.map { try anyLabels.matches(method: "GET", url: #require(URL(string: $0))) }

            #expect(actualOne == expectedOne)
            #expect(actualAny == expectedAny)
        }

        @Test("In a path wildcard * matches within one segment and ** across segments; the whole path must match")
        func pathWildcard() throws {
            let oneSegment = try CompiledNetworkMockMatcher(NetworkMockRule.Matcher(path: .wildcard("/users/*")))
            let anySegments = try CompiledNetworkMockMatcher(NetworkMockRule.Matcher(path: .wildcard("/users/**")))
            let paths = ["/users/7", "/users/", "/users/7/posts", "/users", "/admin/users/7"]
            let expectedOne = [true, true, false, false, false]
            let expectedAny = [true, true, true, false, false]

            let actualOne = try paths.map { try oneSegment.matches(method: "GET", url: #require(URL(string: "https://api.test" + $0))) }
            let actualAny = try paths.map { try anySegments.matches(method: "GET", url: #require(URL(string: "https://api.test" + $0))) }

            #expect(actualOne == expectedOne)
            #expect(actualAny == expectedAny)
        }

        @Test("A wildcard's other characters match themselves, regex metacharacters included")
        func wildcardEscapesMetacharacters() throws {
            let sut = try CompiledNetworkMockMatcher(NetworkMockRule.Matcher(path: .wildcard("/v1.0/items(+)/*")))
            let matching = try #require(URL(string: "https://api.test/v1.0/items(+)/7"))
            let dotAsAny = try #require(URL(string: "https://api.test/v1x0/items(+)/7"))

            let actualMatching = sut.matches(method: "GET", url: matching)
            let actualDotAsAny = sut.matches(method: "GET", url: dotAsAny)

            #expect(actualMatching)
            #expect(!actualDotAsAny)
        }

        @Test("An exact path is case-sensitive, compares the decoded path, and an empty path is /")
        func exactPath() throws {
            let root = try CompiledNetworkMockMatcher(NetworkMockRule.Matcher(path: .exact("/")))
            let spaced = try CompiledNetworkMockMatcher(NetworkMockRule.Matcher(path: .exact("/my files")))
            let noPath = try #require(URL(string: "https://api.test"))
            let encoded = try #require(URL(string: "https://api.test/my%20files"))
            let otherCase = try #require(URL(string: "https://api.test/My%20Files"))

            #expect(root.matches(method: "GET", url: noPath))
            #expect(spaced.matches(method: "GET", url: encoded))
            #expect(!spaced.matches(method: "GET", url: otherCase))
        }

        @Test("A regex matches the whole host or path, an alternation included, and a host regex ignores case")
        func regexIsAnchored() throws {
            let path = try CompiledNetworkMockMatcher(NetworkMockRule.Matcher(path: .regex(#"/users/\d+|/me"#)))
            let host = try CompiledNetworkMockMatcher(NetworkMockRule.Matcher(host: .regex(#"api\d\.test"#)))
            let paths = ["/users/42", "/me", "/users/42/posts", "/users/abc", "/mean"]
            let expected = [true, true, false, false, false]

            let actual = try paths.map { try path.matches(method: "GET", url: #require(URL(string: "https://api.test" + $0))) }
            let actualHost = try host.matches(method: "GET", url: #require(URL(string: "https://API2.TEST/")))

            #expect(actual == expected)
            #expect(actualHost)
        }

        @Test("A regex that doesn't compile throws InvalidRegularExpression with the pattern as written")
        func invalidRegex() {
            let matcher = NetworkMockRule.Matcher(path: .regex("/users/(\\d+"))

            #expect {
                _ = try CompiledNetworkMockMatcher(matcher)
            } throws: { error in
                (error as? InvalidRegularExpression)?.pattern == "/users/(\\d+" && (error as? InvalidRegularExpression)?.reason.isEmpty == false
            }
        }

        @Test("Query items listed must be present with their values; others are ignored")
        func query() throws {
            let sut = try CompiledNetworkMockMatcher(NetworkMockRule.Matcher(query: ["page": "2", "flag": ""]))
            let urls = [
                "https://api.test/list?page=2&flag&sort=asc",
                "https://api.test/list?flag=&page=2",
                "https://api.test/list?page=3&flag",
                "https://api.test/list?page=2",
                "https://api.test/list"
            ]
            let expected = [true, true, false, false, false]

            let actual = try urls.map { try sut.matches(method: "GET", url: #require(URL(string: $0))) }

            #expect(actual == expected)
        }

        @Test("Every part must match: the method, host, path and query")
        func allParts() throws {
            let sut = try CompiledNetworkMockMatcher(NetworkMockRule.Matcher(
                methods: ["GET"], host: .exact("api.test"), path: .wildcard("/v1/*"), query: ["id": "1"]
            ))
            let url = try #require(URL(string: "https://api.test/v1/users?id=1"))
            let otherHost = try #require(URL(string: "https://web.test/v1/users?id=1"))

            #expect(sut.matches(method: "GET", url: url))
            #expect(!sut.matches(method: "POST", url: url))
            #expect(!sut.matches(method: "GET", url: otherHost))
        }

        @Test("A glob becomes an anchored expression: ** any characters, * any but the separator, the rest escaped")
        func globExpression() {
            let expected = #"^\/a\.b\/[^\/]*\/.*$"#

            let actual = CompiledPattern.expression(fromGlob: "/a.b/*/**", separator: "/")

            #expect(actual == expected)
        }
    }
#endif
