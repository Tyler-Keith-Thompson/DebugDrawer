import Foundation

public extension AnalyticsValue {
    /// The value an analytics SDK's untyped property holds, as a `[String: Any]` would hand it
    /// over: strings, numbers, Booleans, dates, `NSNull`, arrays and dictionaries, nested.
    ///
    /// A Boolean stays a Boolean even bridged through `NSNumber`; a whole number is ``int(_:)``
    /// and any other number ``double(_:)``. An optional is its wrapped value, or ``null``. A URL
    /// is its absolute string and a UUID its string; a dictionary whose keys aren't strings uses
    /// their descriptions. Anything else is its description, so no value is lost.
    ///
    /// ```swift
    /// func track(_ event: String, properties: [String: Any]) {
    ///     AnalyticsEvents.record(event, properties: properties.mapValues(AnalyticsValue.init(converting:)))
    ///     sdk.track(event, properties: properties)
    /// }
    /// ```
    ///
    /// - Parameter value: The value to convert.
    init(converting value: Any) {
        if let wrapped = Self.unwrapped(value) {
            self = wrapped.map(Self.init(converting:)) ?? .null
        } else {
            self = Self.scalar(value) ?? Self.container(value) ?? .string(String(describing: value))
        }
    }
}

extension AnalyticsValue {
    /// `value` when it is a string, a number, a Boolean, a date or a null, or a type that reads
    /// as a string; else `nil`.
    fileprivate static func scalar(_ value: Any) -> AnalyticsValue? {
        switch value {
        case let value as AnalyticsValue: value
        case is NSNull: .null
        case let string as String: .string(string)
        case let substring as Substring: .string(String(substring))
        case let date as Date: .date(date)
        case let url as URL: .string(url.absoluteString)
        case let uuid as UUID: .string(uuid.uuidString)
        case let number as NSNumber: AnalyticsValue(number)
        default: nil
        }
    }

    /// `value` when it is an array or a dictionary, its elements converted; else `nil`.
    fileprivate static func container(_ value: Any) -> AnalyticsValue? {
        switch value {
        case let array as [Any]:
            .array(array.map(AnalyticsValue.init(converting:)))
        case let object as [String: Any]:
            .object(object.mapValues(AnalyticsValue.init(converting:)))
        case let object as [AnyHashable: Any]:
            .object(Dictionary(object.map { (String(describing: $0.key.base), AnalyticsValue(converting: $0.value)) }) { first, _ in first })
        default:
            nil
        }
    }

    /// A number as it bridges: a Boolean (`kCFBoolean`), a whole number, or a floating-point one.
    fileprivate init(_ number: NSNumber) {
        if CFGetTypeID(number) == CFBooleanGetTypeID() {
            self = .bool(number.boolValue)
        } else if CFNumberIsFloatType(number) {
            self = .double(number.doubleValue)
        } else if number.compare(NSNumber(value: Int.max)) == .orderedDescending {
            // A UInt64 past Int.max, which int64Value would wrap negative.
            self = .double(number.doubleValue)
        } else {
            self = .int(number.intValue)
        }
    }

    /// `value`'s wrapped value when it is an optional, else `nil`.
    fileprivate static func unwrapped(_ value: Any) -> Any?? {
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .optional else { return nil }
        return .some(mirror.children.first?.value)
    }
}
