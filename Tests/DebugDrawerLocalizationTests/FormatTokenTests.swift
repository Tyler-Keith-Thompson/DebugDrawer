#if DEBUG
    @testable import DebugDrawerLocalization
    import Foundation
    import Testing

    @Suite
    struct FormatTokenTests {
        @Test("A string splits into literal text and specifiers, in order")
        func tokens() {
            let expected: [FormatToken] = [
                .literal("Hi "), .specifier("%1$@"), .literal(", "),
                .specifier("%2$lld"), .literal(" new "), .specifier("%#@items@")
            ]

            let actual = "Hi %1$@, %2$lld new %#@items@".formatTokens

            #expect(actual == expected)
        }

        @Test("The empty string has no tokens, and text without a % is one literal")
        func noSpecifiers() {
            let expectedEmpty: [FormatToken] = []
            let expectedText: [FormatToken] = [.literal("Settings")]

            let empty = "".formatTokens
            let text = "Settings".formatTokens

            #expect(empty == expectedEmpty)
            #expect(text == expectedText)
        }

        // Every string of up to four characters over an alphabet of format-string pieces, split
        // by the plugin and by a reference that matches printf's grammar with a regular
        // expression: an exhaustive table rather than random draws, so nothing needs a seed.
        @Test("Every short string tokenizes as a regular-expression reference does, and the tokens join back into the string")
        func exhaustiveAgainstReference() throws {
            let alphabet: [Character] = ["%", "#", "@", "1", "$", "l", "d", ".", "*", "a", " ", "h"]
            var inputs = [""]
            var frontier = [""]
            for _ in 1 ... 4 {
                frontier = frontier.flatMap { prefix in alphabet.map { prefix + String($0) } }
                inputs += frontier
            }
            // A `.` alone is a precision of zero, as in C's printf.
            let specifier = try Regex(
                [
                    #"%(?:%|#@[^@]+@|"#, // %% or a named plural
                    #"(?:[0-9]+\$)?[-+ #0']*"#, // position and flags
                    #"(?:[0-9]+|\*(?:[0-9]+\$)?)?"#, // width
                    #"(?:\.(?:[0-9]*|\*(?:[0-9]+\$)?))?"#, // precision
                    #"(?:hh|ll|h|l|q|L|z|t|j)?[@dDiuUxXoOfFeEgGaAcCsSpn])"#  // length and conversion
                ].joined(),
                as: Substring.self
            )
            func referenceTokens(_ text: String) -> [FormatToken] {
                var tokens: [FormatToken] = []
                var literal = ""
                var rest = text[...]
                while let first = rest.first {
                    if first == "%", let match = rest.prefixMatch(of: specifier) {
                        if !literal.isEmpty {
                            tokens.append(.literal(literal))
                            literal = ""
                        }
                        tokens.append(.specifier(String(match.output)))
                        rest = rest[match.range.upperBound...]
                    } else {
                        literal.append(first)
                        rest = rest.dropFirst()
                    }
                }
                if !literal.isEmpty {
                    tokens.append(.literal(literal))
                }
                return tokens
            }

            let mismatches = inputs.filter { $0.formatTokens != referenceTokens($0) }
            let unjoined = inputs.filter { input in
                input.formatTokens.map { token in
                    switch token {
                    case let .literal(text), let .specifier(text): text
                    }
                }
                .joined() != input
            }

            #expect(inputs.count == 22621)
            #expect(mismatches.isEmpty, "First mismatches: \(mismatches.prefix(5))")
            #expect(unjoined.isEmpty)
        }

        @Test("Pseudo-localizing every short string keeps its specifiers, accents only its letters, and pads by ceil(0.4 × n)")
        func exhaustivePseudoLocalization() {
            let alphabet: [Character] = ["%", "@", "1", "$", "d", "a", "Z", " ", "l", "é"]
            var inputs: [String] = []
            var frontier = [""]
            for _ in 1 ... 4 {
                frontier = frontier.flatMap { prefix in alphabet.map { prefix + String($0) } }
                inputs += frontier
            }
            let unaccented: [Character: Character] = ["á": "a", "Ž": "Z", "ļ": "l", "ð": "d"]
            func specifiers(_ text: String) -> [String] {
                text.formatTokens.compactMap { token in
                    if case let .specifier(specifier) = token { specifier } else { nil }
                }
            }
            func literalCount(_ text: String) -> Int {
                text.formatTokens.reduce(0) { count, token in
                    if case let .literal(literal) = token { count + literal.count } else { count }
                }
            }

            let failures = inputs.filter { input in
                let actual = PseudoLocalization.transform(input)
                let padding = Int((Double(literalCount(input)) * 0.4).rounded(.up))
                let body = actual.dropFirst().dropLast(padding + 1)
                return !actual.hasPrefix("[") || !actual.hasSuffix(String(repeating: "·", count: padding) + "]")
                    || String(body.map { unaccented[$0] ?? $0 }) != input
                    || specifiers(String(body)) != specifiers(input)
            }

            #expect(inputs.count == 11110)
            #expect(failures.isEmpty, "First failures: \(failures.prefix(5))")
        }
    }
#endif
