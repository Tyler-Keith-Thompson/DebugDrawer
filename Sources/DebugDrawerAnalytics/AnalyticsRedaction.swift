import Foundation

// The mirror's own rules, rather than the drawer's `DebugDrawerRedaction`: that lives in the
// drawer's module, which a release build doesn't link, and it knows headers and JSON paths, where
// an event has properties. Its key matching (a lowercased substring) is repeated here so a key the
// drawer masks is masked the same way. Value patterns are regular expressions because personal data
// that matters most turns up under keys nobody listed (an email address as a `label`, a token in a
// `url`); NSRegularExpression rather than Swift's `Regex`, which is neither `Sendable` nor
// `Equatable` and needs newer systems than the package supports. Rejected: an allow-list of keys
// (every new property would vanish from the sidecar until listed, which hides exactly what QA
// checks), and masking only the matched part of a value (a partial address or token still
// identifies someone).

/// What the analytics mirror masks before an event leaves the app: the value of any property whose
/// key contains one of ``keyPatterns``, at any depth, and any string value, event name or source
/// that one of ``valuePatterns`` matches.
///
/// ```swift
/// let redaction = try AnalyticsRedaction.standard.adding(keys: ["customer_name"], values: [#"\b\d{3}-\d{2}-\d{4}\b"#])
/// try receiver.enable(.analyticsEvents(sessions: sessions, redaction: redaction))
/// ```
///
/// A masked value becomes the string ``mask``, whatever its type was; an object or array under a
/// masked key goes whole. An event's name or source that a value pattern matches is masked too.
/// The event's time, its order and the property keys are kept.
public struct AnalyticsRedaction: Equatable, Sendable {
    /// What a masked value is replaced with.
    public static let mask = "[REDACTED]"

    /// Substrings of a property key that make its value sensitive, lowercased; matched ignoring
    /// case.
    public private(set) var keyPatterns: Set<String>
    /// Regular expressions (`NSRegularExpression` syntax) that make a string value sensitive when
    /// they match any part of it; matched ignoring case.
    public private(set) var valuePatterns: Set<String>
    /// ``valuePatterns``, compiled once.
    private var expressions: [NSRegularExpression]

    /// A value pattern that isn't a regular expression `NSRegularExpression` compiles.
    public struct InvalidPattern: Error, Equatable, Sendable {}

    /// Rules masking the values of keys containing `keys`, and string values matching `values`.
    ///
    /// - Parameters:
    ///   - keys: Substrings of a key, matched ignoring case; an empty one is ignored.
    ///   - values: Regular expressions in `NSRegularExpression` syntax, matched ignoring case.
    /// - Throws: ``InvalidPattern`` when one of `values` isn't a valid regular expression: a rule
    ///   dropped quietly would let through what it was meant to mask.
    public init(keys: some Sequence<String> = [String](), values: some Sequence<String> = [String]()) throws(InvalidPattern) {
        let patterns = Set(values)
        var expressions: [NSRegularExpression] = []
        for pattern in patterns.sorted() {
            guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                throw InvalidPattern()
            }
            expressions.append(expression)
        }
        keyPatterns = Set(keys.map { $0.lowercased() }.filter { !$0.isEmpty })
        valuePatterns = patterns
        self.expressions = expressions
    }

    /// Rules over patterns the caller knows compile: ``standard``'s and ``none``'s constants,
    /// which no input reaches and a test compiles. A pattern that didn't compile would be left out.
    private init(uncheckedKeys keys: [String], values: [String]) {
        keyPatterns = Set(keys)
        valuePatterns = Set(values)
        expressions = valuePatterns.sorted().compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
    }

    /// Personal data and credentials in their usual places: keys containing `email`, `phone`,
    /// `token`, `secret`, `password`, `session`, `auth` or `apikey`/`api_key`/`api-key`, and values
    /// that hold an email address or a JSON Web Token.
    public static let standard = AnalyticsRedaction(
        uncheckedKeys: ["email", "phone", "token", "secret", "password", "session", "auth", "apikey", "api_key", "api-key"],
        values: [
            // An email address anywhere in the value.
            #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
            // A JSON Web Token: three base64url parts, the header's starting `eyJ` (`{"`).
            #"eyJ[A-Z0-9_-]+\.[A-Z0-9_-]+\.[A-Z0-9_-]+"#
        ]
    )

    /// No rules: nothing is masked.
    public static let none = AnalyticsRedaction(uncheckedKeys: [], values: [])

    /// These rules with more key and value patterns.
    ///
    /// - Parameters:
    ///   - keys: More substrings of a key, matched ignoring case.
    ///   - values: More regular expressions, matched ignoring case.
    /// - Returns: The rules with both.
    /// - Throws: ``InvalidPattern`` when one of `values` isn't a valid regular expression.
    public func adding(
        keys: some Sequence<String> = [String](),
        values: some Sequence<String> = [String]()
    ) throws(InvalidPattern) -> AnalyticsRedaction {
        try AnalyticsRedaction(keys: keyPatterns.union(keys.map { $0.lowercased() }), values: valuePatterns.union(values))
    }

    /// Whether a property's value is sensitive because of its key: the key contains one of the key
    /// patterns.
    public func masksKey(_ key: String) -> Bool {
        let key = key.lowercased()
        return keyPatterns.contains { key.contains($0) }
    }

    /// Whether a string value is sensitive: one of the value patterns matches part of it.
    public func masksValue(_ value: String) -> Bool {
        let range = NSRange(value.startIndex..., in: value)
        return expressions.contains { $0.firstMatch(in: value, range: range) != nil }
    }

    /// `properties` with every sensitive value masked, at any depth.
    ///
    /// - Complexity: O(*n* × *p*), where *n* is the number of keys and values and *p* the number of
    ///   patterns.
    public func redacting(_ properties: [String: AnalyticsValue]) -> [String: AnalyticsValue] {
        properties.reduce(into: [:]) { result, property in
            result[property.key] = masksKey(property.key) ? .string(Self.mask) : redacting(property.value)
        }
    }

    /// `value` with every sensitive value in it masked, at any depth.
    func redacting(_ value: AnalyticsValue) -> AnalyticsValue {
        switch value {
        case let .string(string): masksValue(string) ? .string(Self.mask) : value
        case let .array(elements): .array(elements.map(redacting))
        case let .object(object): .object(redacting(object))
        case .int, .double, .bool, .date, .null: value
        }
    }

    /// `text`, an event's name or source, or the mask when a value pattern matches it.
    func redacting(text: String) -> String {
        masksValue(text) ? Self.mask : text
    }

    /// Whether both have the same key and value patterns.
    public static func == (lhs: AnalyticsRedaction, rhs: AnalyticsRedaction) -> Bool {
        lhs.keyPatterns == rhs.keyPatterns && lhs.valuePatterns == rhs.valuePatterns
    }
}
