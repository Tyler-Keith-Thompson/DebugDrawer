#if DEBUG
    @testable import DebugDrawerNetwork
    import Foundation
    import Testing

    struct NetworkMockingAllowedHostTests {
        struct Case: CustomTestStringConvertible, Sendable {
            let entry: NetworkMocking.AllowedHost
            let host: String
            let allows: Bool

            var testDescription: String {
                "\(entry) \(allows ? "allows" : "refuses") \(host.isEmpty ? "an empty host" : host)"
            }
        }

        @Test("An exact entry allows that host alone, ignoring case and a trailing dot", arguments: [
            Case(entry: .exact("api.example.com"), host: "api.example.com", allows: true),
            Case(entry: .exact("api.example.com"), host: "API.Example.COM", allows: true),
            Case(entry: .exact("api.example.com"), host: "api.example.com.", allows: true),
            Case(entry: .exact("API.example.com."), host: "api.example.com", allows: true),
            Case(entry: .exact("api.example.com"), host: "example.com", allows: false),
            Case(entry: .exact("api.example.com"), host: "v2.api.example.com", allows: false),
            Case(entry: .exact("api.example.com"), host: "api.example.com.evil.com", allows: false),
            Case(entry: .exact("api.example.com"), host: "", allows: false),
            Case(entry: .exact(""), host: "", allows: false),
            Case(entry: .exact(""), host: "api.example.com", allows: false)
        ])
        func exact(_ example: Case) {
            let sut = example.entry

            let actual = sut.allows(example.host)

            #expect(actual == example.allows)
        }

        @Test("A domain entry allows the domain and the hosts under it, on a label boundary", arguments: [
            Case(entry: .domain("example.com"), host: "example.com", allows: true),
            Case(entry: .domain("example.com"), host: "api.example.com", allows: true),
            Case(entry: .domain("example.com"), host: "a.b.example.com", allows: true),
            Case(entry: .domain("example.com"), host: "API.EXAMPLE.COM.", allows: true),
            Case(entry: .domain(".example.com"), host: "example.com", allows: true),
            Case(entry: .domain(".example.com"), host: "api.example.com", allows: true),
            Case(entry: .domain("example.com"), host: "badexample.com", allows: false),
            Case(entry: .domain("example.com"), host: "example.com.evil.com", allows: false),
            Case(entry: .domain("example.com"), host: "com", allows: false),
            Case(entry: .domain("example.com"), host: "", allows: false),
            Case(entry: .domain(""), host: "example.com", allows: false),
            Case(entry: .domain("."), host: "example.com", allows: false)
        ])
        func domain(_ example: Case) {
            let sut = example.entry

            let actual = sut.allows(example.host)

            #expect(actual == example.allows)
        }

        @Test("An entry is written as its kind and host, and read back")
        func coding() throws {
            let sut: [NetworkMocking.AllowedHost] = [.exact("api.example.com"), .domain("example.com")]
            let expected = #"[{"host":"api.example.com","kind":"exact"},{"host":"example.com","kind":"domain"}]"#
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys

            let encoded = try encoder.encode(sut)
            let decoded = try JSONDecoder().decode([NetworkMocking.AllowedHost].self, from: encoded)

            #expect(String(bytes: encoded, encoding: .utf8) == expected)
            #expect(decoded == sut)
        }

        @Test("An entry of an unknown kind doesn't decode")
        func unknownKind() {
            let json = Data(#"{"kind":"pattern","host":"*.example.com"}"#.utf8)

            #expect(throws: DecodingError.self) {
                try JSONDecoder().decode(NetworkMocking.AllowedHost.self, from: json)
            }
        }
    }
#endif
