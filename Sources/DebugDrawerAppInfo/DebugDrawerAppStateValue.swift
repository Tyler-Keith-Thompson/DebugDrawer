import Foundation

// A host's value is a string, a number or a Boolean and nothing else: a value of the host's own
// type would decide through its Codable form what reaches the sidecar, and a nested one would be a
// place to put a whole object (a user record, a token's claims) without noticing. It encodes as the
// bare JSON value, as a feature flag's does, so the snapshot and the report read `"plan": "pro"`.

/// A value the host shows a sidecar in the app's state (``DebugDrawerAppStateField``): a string, a
/// number or a Boolean.
///
/// Write a literal where it is one: `"pro"`, `3`, `0.5`, `true`.
public enum DebugDrawerAppStateValue: Hashable, Sendable {
    /// Text.
    case string(String)
    /// A number; JSON writes a whole one without a fraction.
    case number(Double)
    /// A Boolean.
    case bool(Bool)
}

extension DebugDrawerAppStateValue: Codable {
    /// Decodes the bare JSON value: `true` or `false`, a number, or a string.
    ///
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: `DecodingError` when the value is none of the three.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        // JSON's true and false decode only as a Bool, and a number never does, so the order
        // tells the three apart.
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else {
            self = try .string(container.decode(String.self))
        }
    }

    /// Encodes the bare JSON value.
    ///
    /// - Parameter encoder: The encoder to write to.
    /// - Throws: `EncodingError` when the encoder refuses a non-finite number.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        }
    }
}

extension DebugDrawerAppStateValue: ExpressibleByStringLiteral {
    /// A ``string(_:)`` from a literal.
    ///
    /// - Parameter value: The text.
    public init(stringLiteral value: String) {
        self = .string(value)
    }
}

extension DebugDrawerAppStateValue: ExpressibleByIntegerLiteral {
    /// A ``number(_:)`` from a whole literal.
    ///
    /// - Parameter value: The number.
    public init(integerLiteral value: Int) {
        self = .number(Double(value))
    }
}

extension DebugDrawerAppStateValue: ExpressibleByFloatLiteral {
    /// A ``number(_:)`` from a literal with a fraction.
    ///
    /// - Parameter value: The number.
    public init(floatLiteral value: Double) {
        self = .number(value)
    }
}

extension DebugDrawerAppStateValue: ExpressibleByBooleanLiteral {
    /// A ``bool(_:)`` from a literal.
    ///
    /// - Parameter value: The Boolean.
    public init(booleanLiteral value: Bool) {
        self = .bool(value)
    }
}
