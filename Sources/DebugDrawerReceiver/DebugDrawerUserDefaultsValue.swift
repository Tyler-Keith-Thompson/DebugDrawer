import Foundation

// The allowlisted UserDefaults capability's values (DD-127): the four kinds a host may declare a
// key as, and nothing else a defaults key can hold (data, dates, arrays, dictionaries), so a
// sidecar can neither read a structure the host didn't describe nor write one. It encodes as a
// one-key object naming its kind (`{"integer":3}`) rather than the bare JSON value, because JSON
// can't tell 3 from 3.0: a bare `3` sent for a double key would decode as an integer and be
// refused, and an audit log read back would lose which kind a value was. Rejected: the
// synthesized encoding (`{"integer":{"_0":3}}`, noise in every forwarded audit entry), and the
// UserDefaults plugin's `PropertyListValue` (internal to a debug-only plugin, and it holds every
// property-list type, which is what this capability must not).

/// A value of an allowlisted UserDefaults key: a string, a whole number, a number or a Boolean.
///
/// It encodes as a one-key object naming its kind: `{"string":"pro"}`, `{"integer":3}`,
/// `{"double":0.5}`, `{"bool":true}`.
public enum DebugDrawerUserDefaultsValue: Hashable, Sendable {
    /// Text, for a ``DebugDrawerUserDefaultsKey/Kind/string(maximumLength:)`` or
    /// ``DebugDrawerUserDefaultsKey/Kind/choice(options:)`` key.
    case string(String)
    /// A whole number, for an ``DebugDrawerUserDefaultsKey/Kind/integer(range:)`` key.
    case integer(Int)
    /// A finite number, for a ``DebugDrawerUserDefaultsKey/Kind/double(range:)`` key.
    case double(Double)
    /// On or off, for a ``DebugDrawerUserDefaultsKey/Kind/bool`` key.
    case bool(Bool)

    /// The value as UserDefaults stores it.
    var propertyListValue: Any {
        switch self {
        case let .string(text): text
        case let .integer(number): number
        case let .double(number): number
        case let .bool(isOn): isOn
        }
    }
}

extension DebugDrawerUserDefaultsValue: Codable {
    private enum CodingKeys: String, CodingKey {
        case string, integer, double, bool
    }

    /// Decodes a one-key object naming the value's kind.
    ///
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: `DecodingError` when the object doesn't hold exactly one of the four kinds, or
    ///   its value isn't of that kind.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard container.allKeys.count == 1, let key = container.allKeys.first else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "A value names exactly one kind"))
        }
        switch key {
        case .string: self = try .string(container.decode(String.self, forKey: key))
        case .integer: self = try .integer(container.decode(Int.self, forKey: key))
        case .double: self = try .double(container.decode(Double.self, forKey: key))
        case .bool: self = try .bool(container.decode(Bool.self, forKey: key))
        }
    }

    /// Encodes a one-key object naming the value's kind.
    ///
    /// - Parameter encoder: The encoder to write to.
    /// - Throws: The encoder's error.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .string(text): try container.encode(text, forKey: .string)
        case let .integer(number): try container.encode(number, forKey: .integer)
        case let .double(number): try container.encode(number, forKey: .double)
        case let .bool(isOn): try container.encode(isOn, forKey: .bool)
        }
    }
}
