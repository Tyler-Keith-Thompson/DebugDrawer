import Foundation

// Codable is synthesized rather than written as bare JSON values: bare JSON can't tell a date from
// a string, or 3.0 from 3, and the mirror's snapshot must decode to what was recorded.

/// The value of an analytics event's property: what an analytics service accepts, as a value
/// that crosses threads and actors.
///
/// Literals convert on their own, so a call site writes the properties as a dictionary literal:
///
/// ```swift
/// AnalyticsEvents.record("checkout_completed", properties: [
///     "plan": "pro", "seats": 3, "total": 29.99, "trial": false, "coupon": nil,
///     "items": ["sku-1", "sku-2"], "shipping": ["country": "NZ"]
/// ])
/// ```
///
/// A value that isn't a literal takes its case (`.string(user.plan)`), and one from a
/// `[String: Any]` an analytics SDK was handed converts with ``init(converting:)``.
///
/// The type exists in every build, so call sites compile unchanged in release. It is `Codable`,
/// each value keyed by its case, so a sidecar decodes exactly the value the app recorded: a date
/// stays a date and `3.0` a double.
public enum AnalyticsValue: Hashable, Sendable, Codable {
    /// Text, and the string literal.
    case string(String)
    /// A whole number, and the integer literal.
    case int(Int)
    /// A floating-point number, and the float literal; it stays a double even when whole, like `3.0`.
    case double(Double)
    /// A Boolean, and the `true` and `false` literals.
    case bool(Bool)
    /// A moment in time, kept as a date rather than formatted text.
    case date(Date)
    /// No value: JSON's `null`, and the `nil` literal.
    case null
    /// An ordered list of values, and the array literal.
    case array([AnalyticsValue])
    /// Values by key, and the dictionary literal.
    case object([String: AnalyticsValue])
}

extension AnalyticsValue: ExpressibleByStringInterpolation {
    public init(stringLiteral value: String) {
        self = .string(value)
    }
}

extension AnalyticsValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self = .int(value)
    }
}

extension AnalyticsValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self = .double(value)
    }
}

extension AnalyticsValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self = .bool(value)
    }
}

extension AnalyticsValue: ExpressibleByNilLiteral {
    public init(nilLiteral _: ()) {
        self = .null
    }
}

extension AnalyticsValue: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: AnalyticsValue...) {
        self = .array(elements)
    }
}

extension AnalyticsValue: ExpressibleByDictionaryLiteral {
    /// An object of the literal's keys and values; a key written twice keeps its last value.
    public init(dictionaryLiteral elements: (String, AnalyticsValue)...) {
        self = .object(Dictionary(elements) { _, last in last })
    }
}
