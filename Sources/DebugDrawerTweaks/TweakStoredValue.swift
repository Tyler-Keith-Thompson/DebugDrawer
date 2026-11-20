/// A tweak's value as storage holds it: a Boolean, an integer or a string, each a property-list
/// type, so `UserDefaults` stores it as it is.
///
/// It encodes as the bare JSON value (`true`, `3`, `"staging"`), as a sidecar reads and sends it.
public enum TweakStoredValue: Hashable, Sendable {
    /// A toggle's value.
    case bool(Bool)
    /// A stepper's value, or an integer-backed picker's raw value.
    case int(Int)
    /// A text field's value, or a string-backed picker's raw value.
    case string(String)
}

extension TweakStoredValue: CustomStringConvertible {
    /// The value alone: `true`, `3`, `staging`.
    public var description: String {
        switch self {
        case let .bool(value): String(value)
        case let .int(value): String(value)
        case let .string(value): value
        }
    }
}

extension TweakStoredValue: Codable {
    /// Decodes the bare JSON value: a Boolean, then an integer, then a string.
    ///
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: `DecodingError` when the value is none of the three, such as a fractional number.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        // JSON's true and false decode only as a Bool, and a number never does, so the order
        // tells the three apart.
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else {
            self = try .string(container.decode(String.self))
        }
    }

    /// Encodes the bare JSON value.
    ///
    /// - Parameter encoder: The encoder to write to.
    /// - Throws: The encoder's error.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .bool(value): try container.encode(value)
        case let .int(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        }
    }
}

extension TweakStoredValue {
    package var bool: Bool? {
        if case let .bool(value) = self { value } else { nil }
    }

    package var int: Int? {
        if case let .int(value) = self { value } else { nil }
    }

    package var string: String? {
        if case let .string(value) = self { value } else { nil }
    }
}
