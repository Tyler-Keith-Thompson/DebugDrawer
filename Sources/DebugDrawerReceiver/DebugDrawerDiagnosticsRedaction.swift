import Foundation

// The capture's own rules, rather than the drawer's `DebugDrawerRedaction` or the analytics
// mirror's `AnalyticsRedaction`: the first lives in the drawer's module and the second in the
// analytics module, neither of which a production app that captures diagnostics has to link. Its
// header names, key patterns and JSON paths are the drawer's (DD-11), matched the same way, so what
// the drawer masks in a debug build's copy or report is masked here too; its value patterns are the
// analytics mirror's idea, because personal data turns up in free text nobody keyed (an email
// address in a log line, a token in a URL's path). A value pattern masks the text it matches, not
// the whole line or value: a log line keeps what it says around the address it no longer shows.
// NSRegularExpression rather than Swift's `Regex`, which is neither `Sendable` nor `Equatable` and
// needs newer systems than the package supports.
//
// Free text is also read for `key=value` and `key: value` pairs, whose values are masked when the
// key contains a key pattern, by the same function the drawer's rules use for the Console's copies
// and report (`maskingKeyValuePairs(with:where:)`), so both mask the same pairs.
//
// Rejected: sharing one redaction type through the receiver with the drawer and the analytics
// mirror (a source break for both, for no new behavior); keeping a body that isn't JSON with value
// patterns applied (a form body, a multipart upload or a protobuf carries secrets under names no
// pattern reads, so it is left out and only its size kept); and leaving log text unredacted (a
// production capture holds real customers' data).

/// What a diagnostics capture masks before anything it captures is kept: header values by name,
/// values under sensitive keys (URL query items, JSON keys, log metadata keys, and `key=value` or
/// `key: value` pairs in text) or at JSON paths, and the text any value pattern matches in a log
/// line, a metadata value, a header value, a URL or a JSON string.
///
/// ```swift
/// let redaction = DebugDrawerDiagnosticsRedaction.standard.adding(keys: ["customer"], values: [#"\bACCT-\d{6}\b"#])
/// let capture = DebugDrawerDiagnosticsCapture(sessions: sessions, redaction: redaction)
/// ```
///
/// A masked value becomes ``mask``. A JSON path is dot-separated object keys from the document's
/// root (`user.password`); `*` matches any one key, and arrays are transparent, so `items.token`
/// matches the `token` of every element of `items`. Names, keys and patterns match ignoring case.
/// A request or response body is kept only when it is JSON, redacted by these rules; any other body
/// is left out, its size kept.
public struct DebugDrawerDiagnosticsRedaction: Equatable, Sendable {
    /// What a masked value, or the text a value pattern matched, is replaced with.
    public static let mask = "[REDACTED]"

    /// Header names whose values are masked, lowercased.
    public private(set) var headerNames: Set<String>
    /// Substrings of a key that make its value sensitive, lowercased: a header's name, a URL query
    /// item's, a JSON key or a log line's metadata key.
    public private(set) var keyPatterns: Set<String>
    /// JSON paths whose values are masked.
    public private(set) var jsonPaths: Set<String>
    /// Regular expressions (`NSRegularExpression` syntax) whose matches are masked wherever text is
    /// kept; matched ignoring case.
    public private(set) var valuePatterns: Set<String>
    /// ``valuePatterns``, compiled once.
    private var expressions: [NSRegularExpression]

    /// Rules masking the given header names, keys containing the given patterns, the given JSON
    /// paths, and the text the given regular expressions match.
    ///
    /// - Parameters:
    ///   - headers: Header names, matched ignoring case.
    ///   - keys: Substrings of a key, matched ignoring case; an empty one is ignored.
    ///   - jsonPaths: Dot-separated JSON paths, `*` for any key.
    ///   - values: Regular expressions in `NSRegularExpression` syntax, matched ignoring case.
    /// - Precondition: Each of `values` is a valid regular expression.
    public init(
        headers: some Sequence<String> = [String](),
        keys: some Sequence<String> = [String](),
        jsonPaths: some Sequence<String> = [String](),
        values: some Sequence<String> = [String]()
    ) {
        headerNames = Set(headers.map { $0.lowercased() })
        keyPatterns = Set(keys.map { $0.lowercased() }.filter { !$0.isEmpty })
        self.jsonPaths = Set(jsonPaths)
        valuePatterns = Set(values)
        expressions = valuePatterns.sorted().map { pattern in
            // A pattern is the host's own literal, so a bad one is a programming error found the
            // first time the app runs, not an input to recover from; and a rule silently dropped
            // would let what it was meant to mask through.
            guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                preconditionFailure("DebugDrawerDiagnosticsRedaction's value pattern \(pattern) isn't a valid regular expression")
            }
            return expression
        }
    }

    /// Credentials and personal data in their usual places: the `Authorization`,
    /// `Proxy-Authorization`, `Cookie` and `Set-Cookie` headers; keys containing `token`, `secret`,
    /// `password`, `session`, `auth`, `apikey`/`api_key`/`api-key`, `email` or `phone`; and text
    /// that is an email address, a JSON Web Token, a bearer credential (`Bearer …`) or a secret
    /// written as `password=…`, `token: …` and the like.
    public static let standard = DebugDrawerDiagnosticsRedaction(
        headers: ["Authorization", "Proxy-Authorization", "Cookie", "Set-Cookie"],
        keys: ["token", "secret", "password", "session", "auth", "apikey", "api_key", "api-key", "email", "phone"],
        values: [
            // An email address.
            #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
            // A JSON Web Token: three base64url parts, the header's starting `eyJ` (`{"`).
            #"eyJ[A-Z0-9_-]+\.[A-Z0-9_-]+\.[A-Z0-9_-]+"#,
            // A bearer credential, as an Authorization header's value is often logged.
            #"\bBearer\s+[A-Z0-9._~+/-]+=*"#,
            // A secret written out with its name: `password=hunter2`, `token: abc`.
            #"\b(?:password|passwd|secret|token|api[_-]?key)\b\s*[:=]\s*[^\s,;&]+"#
        ]
    )

    /// No rules: nothing is masked, though a body that isn't JSON is still left out.
    public static let none = DebugDrawerDiagnosticsRedaction()

    /// These rules with more header names, key patterns, JSON paths and value patterns.
    ///
    /// - Parameters:
    ///   - headers: More header names.
    ///   - keys: More substrings of a key.
    ///   - jsonPaths: More JSON paths.
    ///   - values: More regular expressions.
    /// - Returns: The rules with both.
    /// - Precondition: Each of `values` is a valid regular expression.
    public func adding(
        headers: some Sequence<String> = [String](),
        keys: some Sequence<String> = [String](),
        jsonPaths: some Sequence<String> = [String](),
        values: some Sequence<String> = [String]()
    ) -> DebugDrawerDiagnosticsRedaction {
        DebugDrawerDiagnosticsRedaction(
            headers: headerNames.union(headers.map { $0.lowercased() }),
            keys: keyPatterns.union(keys.map { $0.lowercased() }),
            jsonPaths: self.jsonPaths.union(jsonPaths),
            values: valuePatterns.union(values)
        )
    }

    /// Whether both have the same rules.
    public static func == (lhs: DebugDrawerDiagnosticsRedaction, rhs: DebugDrawerDiagnosticsRedaction) -> Bool {
        lhs.headerNames == rhs.headerNames && lhs.keyPatterns == rhs.keyPatterns
            && lhs.jsonPaths == rhs.jsonPaths && lhs.valuePatterns == rhs.valuePatterns
    }

    /// Whether a key's value is sensitive: the key contains one of the key patterns.
    package func masksKey(_ key: String) -> Bool {
        let key = key.lowercased()
        return keyPatterns.contains { key.contains($0) }
    }

    /// Whether a header's value is sensitive: its name is a listed header or contains a key
    /// pattern.
    package func masksHeader(_ name: String) -> Bool {
        headerNames.contains(name.lowercased()) || masksKey(name)
    }

    /// `text` with the value of every `key=value` and `key: value` pair whose key contains a key
    /// pattern masked (read as `maskingKeyValuePairs(with:where:)` reads them), then every match of
    /// a value pattern.
    ///
    /// - Complexity: O(*n* × *p*), where *n* is the length of `text` and *p* the number of
    ///   patterns.
    package func redacting(text: String) -> String {
        let pairsMasked = keyPatterns.isEmpty ? text : text.maskingKeyValuePairs(with: Self.mask, where: masksKey)
        return expressions.reduce(pairsMasked) { text, expression in
            expression.stringByReplacingMatches(
                in: text, range: NSRange(text.startIndex..., in: text), withTemplate: NSRegularExpression.escapedTemplate(for: Self.mask)
            )
        }
    }

    /// Key/value fields with each sensitive key's value masked, and value patterns masked in the
    /// rest.
    package func redacting(fields: [String: String]) -> [String: String] {
        fields.reduce(into: [:]) { result, field in
            result[field.key] = masksKey(field.key) ? Self.mask : redacting(text: field.value)
        }
    }

    /// Headers with each sensitive header's value masked, and value patterns masked in the rest.
    package func redacting(headers: [String: String]) -> [String: String] {
        headers.reduce(into: [:]) { result, header in
            result[header.key] = masksHeader(header.key) ? Self.mask : redacting(text: header.value)
        }
    }

    /// A URL with its user and password, and each sensitive query item's value, masked, and value
    /// patterns masked in its path, its other query values and its fragment; never in its host. The
    /// mask is written as it is, not percent-encoded: the result is for reading, not loading.
    package func redacting(url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return redacting(text: url.absoluteString)
        }
        if components.user != nil {
            components.user = Self.mask
        }
        if components.password != nil {
            components.password = Self.mask
        }
        components.path = redacting(text: components.path)
        if let items = components.queryItems {
            components.queryItems = items.map { item in
                guard let value = item.value else { return item }
                return URLQueryItem(name: item.name, value: masksKey(item.name) ? Self.mask : redacting(text: value))
            }
        }
        if let fragment = components.fragment {
            components.fragment = redacting(text: fragment)
        }
        // Each part separately: a pattern run over the whole URL could match across them (an email
        // address pattern takes `user@host`), and mask the host.
        let encodedMask = Self.mask.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? Self.mask
        return (components.string ?? url.absoluteString).replacingOccurrences(of: encodedMask, with: Self.mask)
    }

    /// A JSON body with every value under a sensitive key or at a JSON path masked, and value
    /// patterns masked in every string, re-encoded with sorted keys; `nil` when `body` isn't JSON.
    package func redacting(json body: Data) -> Data? {
        guard let object = try? JSONSerialization.jsonObject(with: body, options: [.fragmentsAllowed]) else { return nil }
        let paths = jsonPaths.map { $0.split(separator: ".").map(String.init) }
        return try? JSONSerialization.data(
            withJSONObject: redact(object, at: [], paths: paths),
            options: [.sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed]
        )
    }
}

extension DebugDrawerDiagnosticsRedaction {
    // JSONSerialization hands back Foundation containers; walking them keeps the document's own
    // types (numbers, nulls) wherever nothing is masked.
    fileprivate func redact(_ value: Any, at path: [String], paths: [[String]]) -> Any {
        switch value {
        case let object as [String: Any]:
            object.reduce(into: [String: Any]()) { result, member in
                let childPath = path + [member.key]
                result[member.key] = masksKey(member.key) || paths.contains(where: { $0.matches(childPath) })
                    ? Self.mask
                    : redact(member.value, at: childPath, paths: paths)
            }
        case let array as [Any]:
            array.map { redact($0, at: path, paths: paths) }
        case let string as String:
            redacting(text: string)
        default:
            value
        }
    }
}

extension [String] {
    /// Whether this JSON path (components, `*` for any key) names the given key path.
    fileprivate func matches(_ keyPath: [String]) -> Bool {
        count == keyPath.count && zip(self, keyPath).allSatisfy { $0 == "*" || $0 == $1 }
    }
}
