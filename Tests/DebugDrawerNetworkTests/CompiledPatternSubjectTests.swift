#if DEBUG
    @testable import DebugDrawerNetwork
    import Foundation
    import Testing

    struct CompiledPatternSubjectTests {
        struct Case: CustomTestStringConvertible, Sendable {
            let pattern: NetworkMockRule.Pattern
            let separator: Character
            let caseInsensitive: Bool

            var testDescription: String {
                "\(pattern), \(caseInsensitive ? "ignoring case" : "matching case")"
            }
        }

        @Test("A pattern matches text made once into a Subject exactly as it matches the text itself", arguments: [
            Case(pattern: .any, separator: ".", caseInsensitive: true),
            Case(pattern: .exact("api.example.com"), separator: ".", caseInsensitive: true),
            Case(pattern: .exact("/v1/Orders"), separator: "/", caseInsensitive: false),
            Case(pattern: .wildcard("*.example.com"), separator: ".", caseInsensitive: true),
            Case(pattern: .wildcard("**.example.com"), separator: ".", caseInsensitive: true),
            Case(pattern: .wildcard("/v1/*"), separator: "/", caseInsensitive: false),
            Case(pattern: .wildcard("/v1/**"), separator: "/", caseInsensitive: false),
            Case(pattern: .wildcard("/café/*"), separator: "/", caseInsensitive: false),
            Case(pattern: .regex("/v[0-9]+/orders/[0-9]+"), separator: "/", caseInsensitive: false),
            Case(pattern: .regex("a|b"), separator: "/", caseInsensitive: false),
            Case(pattern: .regex(""), separator: "/", caseInsensitive: false)
        ])
        func subjectMatchesAsText(_ testCase: Case) throws {
            let sut = try CompiledPattern(testCase.pattern, separator: testCase.separator, caseInsensitive: testCase.caseInsensitive)
            // Empty text, case, a final line terminator (which ICU's $ matches before), one inside,
            // a separator crossed, non-ASCII, and a character of two UTF-16 code units.
            let texts: [String] = [
                "", "/", "a", "b", "ab", "api.example.com", "API.Example.COM", "a.b.example.com", "example.com",
                "api.example.com\n", "/v1/orders", "/v1/Orders", "/V1/orders", "/v1/orders\n", "/v1/or\nders",
                "/v1/orders/7", "/v12/orders/34", "/café/x", "/cafe\u{301}/x", "/v1/🦊", "/🦊/v1/x"
            ]
            let expected = texts.map { sut.matches($0) }

            let actual = texts.map { sut.matches(CompiledPattern.Subject($0)) }

            #expect(actual == expected)
        }
    }
#endif
