#if DEBUG
    import Foundation

    /// A pattern that isn't a valid regular expression, from compiling a wildcard or a regex.
    struct InvalidRegularExpression: Error, Equatable {
        /// The pattern as written.
        let pattern: String
        /// Why it doesn't compile, in the words `NSRegularExpression` gives.
        let reason: String
    }

    /// A rule's matcher with its patterns compiled, once, to match requests from any thread.
    struct CompiledNetworkMockMatcher: Sendable {
        let methods: Set<String>
        let host: CompiledPattern
        let path: CompiledPattern
        let query: [String: String]

        /// Compiles `matcher`'s patterns.
        ///
        /// - Throws: `InvalidRegularExpression` for a regex that doesn't compile. A wildcard
        ///   always compiles.
        init(_ matcher: NetworkMockRule.Matcher) throws(InvalidRegularExpression) {
            methods = matcher.methods
            host = try CompiledPattern(matcher.host, separator: ".", caseInsensitive: true)
            path = try CompiledPattern(matcher.path, separator: "/", caseInsensitive: false)
            query = matcher.query
        }

        /// Whether a request of `method` to `url` matches.
        ///
        /// - Complexity: O(*n*) in the URL's length, for a wildcard or a regex without
        ///   backtracking.
        func matches(method: String, url: URL) -> Bool {
            guard methods.isEmpty || methods.contains(method.uppercased()) else { return false }
            guard host.matches(url.host() ?? "") else { return false }
            let path = url.path(percentEncoded: false)
            guard self.path.matches(path.isEmpty ? "/" : path) else { return false }
            guard !query.isEmpty else { return true }
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            return query.allSatisfy { name, value in
                items.contains { $0.name == name && ($0.value ?? "") == value }
            }
        }
    }

    /// A host or path pattern, ready to match: wildcards are translated to regular expressions.
    enum CompiledPattern: Sendable {
        case any
        case exact(String, caseInsensitive: Bool)
        case expression(RegularExpression)

        /// `NSRegularExpression` is immutable and documented as safe to use from any thread; the
        /// SDK doesn't mark it `Sendable`, so this box says so.
        struct RegularExpression: @unchecked Sendable {
            let expression: NSRegularExpression
        }

        /// - Parameters:
        ///   - pattern: The pattern as written.
        ///   - separator: What a single `*` doesn't cross: `.` in a host, `/` in a path.
        ///   - caseInsensitive: Whether case is ignored.
        init(_ pattern: NetworkMockRule.Pattern, separator: Character, caseInsensitive: Bool) throws(InvalidRegularExpression) {
            switch pattern {
            case .any:
                self = .any
            case let .exact(text):
                self = .exact(text, caseInsensitive: caseInsensitive)
            case let .wildcard(glob):
                let expression = Self.expression(fromGlob: glob, separator: separator)
                self = try .expression(Self.compile(expression, as: glob, caseInsensitive: caseInsensitive))
            case let .regex(expression):
                // Grouped, so an alternation inside stays inside the anchors.
                self = try .expression(Self.compile("^(?:\(expression))$", as: expression, caseInsensitive: caseInsensitive))
            }
        }

        /// Whether `text` matches, whole.
        func matches(_ text: String) -> Bool {
            switch self {
            case .any:
                true
            case let .exact(expected, caseInsensitive):
                caseInsensitive ? text.caseInsensitiveCompare(expected) == .orderedSame : text == expected
            case let .expression(box):
                box.expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
            }
        }

        /// The anchored regular expression for a glob: `**` matches anything, `*` anything but
        /// `separator`, and every other character itself.
        static func expression(fromGlob glob: String, separator: Character) -> String {
            let notSeparator = "[^" + NSRegularExpression.escapedPattern(for: String(separator)) + "]*"
            var expression = "^"
            var literal = ""
            var index = glob.startIndex
            while index < glob.endIndex {
                if glob[index] == "*" {
                    expression += NSRegularExpression.escapedPattern(for: literal)
                    literal = ""
                    let next = glob.index(after: index)
                    if next < glob.endIndex, glob[next] == "*" {
                        expression += ".*"
                        index = glob.index(after: next)
                    } else {
                        expression += notSeparator
                        index = next
                    }
                } else {
                    literal.append(glob[index])
                    index = glob.index(after: index)
                }
            }
            return expression + NSRegularExpression.escapedPattern(for: literal) + "$"
        }

        private static func compile(
            _ expression: String,
            as written: String,
            caseInsensitive: Bool
        ) throws(InvalidRegularExpression) -> RegularExpression {
            do {
                let options: NSRegularExpression.Options = caseInsensitive ? [.caseInsensitive] : []
                return try RegularExpression(expression: NSRegularExpression(pattern: expression, options: options))
            } catch {
                // The reason quotes the anchored expression; the person wrote the pattern alone.
                let reason = ((error as NSError).localizedFailureReason ?? error.localizedDescription)
                    .replacingOccurrences(of: expression, with: written)
                throw InvalidRegularExpression(pattern: written, reason: reason)
            }
        }
    }
#endif
