// Foundation only, and in every build: the adapter's vocabulary is shared with tools beyond the
// drawer, so it carries no drawer or SwiftUI types.
import Foundation

/// A feature flag's value: a Boolean, a number or a string, the kinds every flag service serves.
///
/// It encodes as the bare JSON value (`true`, `0.25`, `"blue"`). The type exists in every build so
/// a ``FeatureFlagProvider`` conformance compiles unchanged in release.
public enum FeatureFlagValue: Hashable, Sendable {
    /// An on-off flag.
    case bool(Bool)
    /// A numeric flag, integer or not.
    case number(Double)
    /// A string flag: a variant name, a color, a URL.
    case string(String)
}

extension FeatureFlagValue: CustomStringConvertible {
    /// The value alone: `true`, `3`, `0.25`, `blue`. A whole number shows no fraction.
    public var description: String {
        switch self {
        case let .bool(value):
            String(value)
        case let .number(value):
            // Whole numbers within Int's range print as integers ("3", not "3.0").
            if value.rounded() == value, abs(value) < 1e15 {
                String(Int(value))
            } else {
                String(value)
            }
        case let .string(value):
            value
        }
    }
}

extension FeatureFlagValue: Codable {
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

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .bool(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        }
    }
}
