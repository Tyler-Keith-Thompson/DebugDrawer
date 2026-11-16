/// A tweak's value as storage holds it: a Boolean, an integer or a string, each a property-list
/// type, so `UserDefaults` stores it as it is.
///
/// The type exists in every build so a ``TweakStorage`` conformance compiles unchanged in release.
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

extension TweakStoredValue {
    var bool: Bool? {
        if case let .bool(value) = self { value } else { nil }
    }

    var int: Int? {
        if case let .int(value) = self { value } else { nil }
    }

    var string: String? {
        if case let .string(value) = self { value } else { nil }
    }
}
