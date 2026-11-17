#if DEBUG
    @testable import DebugDrawerNetworkPlugin
    import Foundation
    import Testing

    @Suite
    struct NetworkIgnoredDomainTests {
        @Test(
            "A domain hides itself and its subdomains, on label boundaries",
            arguments: [
                ("example.com", true),
                ("cdn.example.com", true),
                ("a.b.cdn.example.com", true),
                ("badexample.com", false),
                ("example.com.evil.net", false),
                ("example.co", false),
                ("com", false),
                ("", false)
            ]
        )
        func labelBoundaries(host: String, expected: Bool) throws {
            let sut = try NetworkIgnoredDomain(parsing: "example.com")

            let actual = sut.matches(host: host)

            #expect(actual == expected)
        }

        @Test("Matching ignores case, in the domain typed and in the request's host")
        func caseInsensitive() throws {
            let sut = try NetworkIgnoredDomain(parsing: "Analytics.EXAMPLE.com")

            let actual = sut.matches(host: "CDN.analytics.Example.COM")

            let expectedName = "analytics.example.com"
            #expect(sut.name == expectedName)
            #expect(actual)
        }

        @Test("A trailing dot, the DNS root, is dropped from the domain and ignored in the host")
        func trailingDots() throws {
            let sut = try NetworkIgnoredDomain(parsing: "example.com.")

            let actual = [sut.matches(host: "cdn.example.com."), sut.matches(host: "example.com")]

            let expectedName = "example.com"
            #expect(sut.name == expectedName)
            #expect(actual == [true, true])
        }

        @Test(
            "A port, a scheme, a path and user information are dropped: only the host is kept",
            arguments: [
                ("localhost:8080", "localhost"),
                ("https://cdn.example.com/images/a.png?size=2", "cdn.example.com"),
                ("wss://user:secret@chat.example.com:443/socket", "chat.example.com"),
                ("example.com/path", "example.com"),
                ("  Example.com  ", "example.com"),
                ("[::1]:8080", "::1"),
                ("[2001:db8::1]", "2001:db8::1"),
                ("2001:DB8::1", "2001:db8::1"),
                ("192.168.0.1:3000", "192.168.0.1")
            ]
        )
        func keepsTheHost(text: String, expected: String) throws {
            let actual = try NetworkIgnoredDomain(parsing: text).name

            #expect(actual == expected)
        }

        @Test("An IPv4 address hides that address alone: not addresses that end the same")
        func ipv4IsExact() throws {
            let sut = try NetworkIgnoredDomain(parsing: "10.0.0.1")

            let actual = ["10.0.0.1", "110.0.0.1", "1.10.0.0.1", "10.0.0.10"].map { sut.matches(host: $0) }

            #expect(actual == [true, false, false, false])
        }

        @Test("An IPv6 address hides that address alone, with or without brackets in the host")
        func ipv6IsExact() throws {
            let sut = try NetworkIgnoredDomain(parsing: "::1")

            let actual = ["::1", "[::1]", "::11", "fe80::1"].map { sut.matches(host: $0) }

            #expect(actual == [true, true, false, false])
        }

        @Test("Blank text is refused as empty")
        func emptyInput() {
            #expect(throws: NetworkIgnoredDomain.ParseError.empty) { try NetworkIgnoredDomain(parsing: "  \n") }
        }

        @Test("A wildcard is refused: a domain already covers its subdomains", arguments: ["*.example.com", "cdn.*.com", "*"])
        func wildcardInput(text: String) {
            #expect(throws: NetworkIgnoredDomain.ParseError.wildcard) { try NetworkIgnoredDomain(parsing: text) }
        }

        @Test(
            "Text that isn't a host is refused as malformed",
            arguments: [
                "exa mple.com", "-bad.example.com", "bad-.example.com", "a..b.com", ".", "example.com:http", "example.com:123456",
                "0.1", "256.1.1.1", "1.2.3", "bücher.de", "[::1", "[::1]x", "fe80::1::2", "https://", "café"
            ]
        )
        func malformedInput(text: String) {
            #expect(throws: NetworkIgnoredDomain.ParseError.malformed) { try NetworkIgnoredDomain(parsing: text) }
        }

        @Test("A label of 63 characters is a host; one of 64 isn't")
        func labelLengthBoundary() throws {
            let longest = String(repeating: "a", count: 63) + ".com"
            let tooLong = String(repeating: "a", count: 64) + ".com"

            let actual = try NetworkIgnoredDomain(parsing: longest).name

            #expect(actual == longest)
            #expect(throws: NetworkIgnoredDomain.ParseError.malformed) { try NetworkIgnoredDomain(parsing: tooLong) }
        }

        @Test("A one-label host such as localhost is a domain, and hides its subdomains")
        func singleLabel() throws {
            let sut = try NetworkIgnoredDomain(parsing: "localhost")

            let actual = [sut.matches(host: "localhost"), sut.matches(host: "api.localhost"), sut.matches(host: "mylocalhost")]

            #expect(actual == [true, true, false])
        }

        @Test("Each refusal says what to type instead")
        func messages() {
            let expected = [
                "Enter a host or domain, such as example.com.",
                "Leave out the *: example.com covers its subdomains too.",
                "Not a host: use letters, digits, hyphens and dots, such as cdn.example.com, or an IP address."
            ]

            let actual = [NetworkIgnoredDomain.ParseError.empty, .wildcard, .malformed].map(\.message)

            #expect(actual == expected)
        }

        @Test("The choices for a host are the host, then each parent domain down to two labels")
        func choicesForDeepHost() {
            let actual = NetworkIgnoredDomain.choices(forHost: "cdn.img.Example.com").map(\.name)

            #expect(actual == ["cdn.img.example.com", "img.example.com", "example.com"])
        }

        @Test(
            "A two-label host, a one-label host and an address offer themselves alone; no host offers nothing",
            arguments: [("example.com", ["example.com"]), ("localhost", ["localhost"]), ("10.0.0.1", ["10.0.0.1"]), ("::1", ["::1"]), ("", [])]
        )
        func choicesForShortHosts(host: String, expected: [String]) {
            let actual = NetworkIgnoredDomain.choices(forHost: host).map(\.name)

            #expect(actual == expected)
        }

        @Test("Suffix matching agrees with comparing labels from the end, for every pair of hosts here")
        func agreesWithLabelComparison() throws {
            let hosts = ["example.com", "cdn.example.com", "badexample.com", "a.cdn.example.com", "example.org", "com", "x.y", "y", "ample.com"]
            // A naive reference: the domain's labels are the host's last labels.
            func reference(_ domain: String, _ host: String) -> Bool {
                let domainLabels = domain.split(separator: ".")
                let hostLabels = host.split(separator: ".")
                return hostLabels.count >= domainLabels.count && Array(hostLabels.suffix(domainLabels.count)) == domainLabels
            }
            var mismatches: [String] = []

            for domain in hosts {
                let sut = try NetworkIgnoredDomain(parsing: domain)
                for host in hosts where sut.matches(host: host) != reference(domain, host) {
                    mismatches.append("\(domain) / \(host)")
                }
            }

            #expect(mismatches.isEmpty)
        }

        @Test("An app's seed that isn't a host is skipped rather than trapped on")
        func seedSkipsMalformed() {
            let actual = ["analytics.example.com", "not a host", "*.cdn.example.com"].compactMap(NetworkIgnoredDomain.seed).map(\.name)

            #expect(actual == ["analytics.example.com"])
        }
    }
#endif
