import Foundation

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
/// The type exists in every build, so call sites compile unchanged in release.
public enum AnalyticsValue: Hashable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case date(Date)
    /// No value: JSON's `null`, and the `nil` literal.
    case null
    case array([AnalyticsValue])
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
