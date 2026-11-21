import Foundation

/// A pattern that isn't a valid regular expression, from compiling a wildcard or a regex.
package struct InvalidRegularExpression: Error, Equatable {
    /// The pattern as written.
    package let pattern: String
    /// Why it doesn't compile, in the words `NSRegularExpression` gives.
    package let reason: String
}

/// A rule's matcher with its patterns compiled, once, to match requests from any thread.
package struct CompiledNetworkMockMatcher: Sendable {
    package let methods: Set<String>
    package let host: CompiledPattern
    package let path: CompiledPattern
    package let query: [String: String]

    /// Compiles `matcher`'s patterns.
    ///
    /// - Throws: `InvalidRegularExpression` for a regex that doesn't compile. A wildcard
    ///   always compiles.
    package init(_ matcher: NetworkMockRule.Matcher) throws(InvalidRegularExpression) {
        methods = matcher.methods
        host = try CompiledPattern(matcher.host, separator: ".", caseInsensitive: true)
        path = try CompiledPattern(matcher.path, separator: "/", caseInsensitive: false)
        query = matcher.query
    }

    /// Whether a request of `method` to `url` matches.
    ///
    /// Works out the request's method, host and path for this one rule; to try a request against
    /// several rules, make its `Request` once and use `matches(_:)`.
    ///
    /// - Complexity: O(*n*) in the URL's length, for a wildcard or a regex without
    ///   backtracking.
    package func matches(method: String, url: URL) -> Bool {
        matches(Request(method: method, url: url))
    }

    /// Whether `request` matches.
    ///
    /// - Complexity: O(*n*) in the URL's length, for a wildcard or a regex without
    ///   backtracking.
    package func matches(_ request: Request) -> Bool {
        guard methods.isEmpty || methods.contains(request.method) else { return false }
        guard host.matches(request.host) else { return false }
        guard path.matches(request.path) else { return false }
        guard !query.isEmpty else { return true }
        let items = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return query.allSatisfy { name, value in
            items.contains { $0.name == name && ($0.value ?? "") == value }
        }
    }

    // None of these depends on the rule, and working them out per rule, each regular expression
    // bridging its text to an NSString again, was most of what a rule cost (DD-285).
    /// A request as every rule compares it: its method, host and path worked out once, however
    /// many rules it is tried against.
    package struct Request {
        /// The method, uppercased.
        let method: String
        /// The URL's host; empty when it has none.
        let host: CompiledPattern.Subject
        /// The URL's path, percent-decoded; `/` when it is empty.
        let path: CompiledPattern.Subject
        /// The URL, whose query only rules with query items read.
        let url: URL

        /// - Parameters:
        ///   - method: The request's HTTP method, in any case.
        ///   - url: The request's URL.
        package init(method: String, url: URL) {
            self.method = method.uppercased()
            host = CompiledPattern.Subject(url.host() ?? "")
            let path = url.path(percentEncoded: false)
            self.path = CompiledPattern.Subject(path.isEmpty ? "/" : path)
            self.url = url
        }
    }
}

/// A host or path pattern, ready to match: wildcards are translated to regular expressions.
package enum CompiledPattern: Sendable {
    case any
    case exact(String, caseInsensitive: Bool)
    case expression(RegularExpression)

    /// `NSRegularExpression` is immutable and documented as safe to use from any thread; the
    /// SDK doesn't mark it `Sendable`, so this box says so.
    package struct RegularExpression: @unchecked Sendable {
        package let expression: NSRegularExpression
    }

    /// - Parameters:
    ///   - pattern: The pattern as written.
    ///   - separator: What a single `*` doesn't cross: `.` in a host, `/` in a path.
    ///   - caseInsensitive: Whether case is ignored.
    package init(_ pattern: NetworkMockRule.Pattern, separator: Character, caseInsensitive: Bool) throws(InvalidRegularExpression) {
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

    /// Text to match against several patterns, bridged to an `NSString` once.
    ///
    /// A regular expression reads an `NSString`: given a Swift string, it bridges it anew on every
    /// call, which allocates. This holds a string backed by an `NSString`, which bridges for free,
    /// and its range.
    package struct Subject {
        /// The text, backed by an `NSString`.
        let text: String
        /// The whole of `text`, in UTF-16 code units.
        let range: NSRange

        /// - Parameter text: The text.
        package init(_ text: String) {
            let bridged = NSString(string: text)
            self.text = bridged as String
            range = NSRange(location: 0, length: bridged.length)
        }
    }

    /// Whether `text` matches, whole.
    ///
    /// For text matched against several patterns, make its `Subject` once and match that.
    package func matches(_ text: String) -> Bool {
        switch self {
        case .any:
            true
        case let .exact(expected, caseInsensitive):
            caseInsensitive ? text.caseInsensitiveCompare(expected) == .orderedSame : text == expected
        case let .expression(box):
            box.expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
        }
    }

    /// Whether `subject` matches, whole.
    package func matches(_ subject: Subject) -> Bool {
        switch self {
        case .any:
            true
        case let .exact(expected, caseInsensitive):
            caseInsensitive ? subject.text.caseInsensitiveCompare(expected) == .orderedSame : subject.text == expected
        case let .expression(box):
            // Whether there is a match at all: unlike firstMatch(in:range:), counting them makes no
            // NSTextCheckingResult. The pattern is anchored at both ends, so there is at most one.
            box.expression.numberOfMatches(in: subject.text, range: subject.range) > 0
        }
    }

    /// The anchored regular expression for a glob: `**` matches anything, `*` anything but
    /// `separator`, and every other character itself.
    package static func expression(fromGlob glob: String, separator: Character) -> String {
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
