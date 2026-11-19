import Foundation

// The receiver's own flag vocabulary, apart from the Feature Flags plugin's `FeatureFlag` and
// `FeatureFlagValue`: that plugin depends on the drawer, which a release build doesn't link, so a
// host adapts its flag service to both where it uses both. The value encodes as the bare JSON
// value, as the plugin's does, so a sidecar reads either the same way.

/// A feature flag's value: a Boolean, a number or a string, the kinds every flag service serves.
///
/// It encodes as the bare JSON value (`true`, `0.25`, `"blue"`).
public enum DebugDrawerFeatureFlagValue: Hashable, Sendable {
    /// An on-off flag.
    case bool(Bool)
    /// A numeric flag, integer or not.
    case number(Double)
    /// A string flag: a variant name, a color, a URL.
    case string(String)

    /// Whether `other` is a value of the same kind: an override never changes a flag's kind.
    func isSameKind(as other: Self) -> Bool {
        switch (self, other) {
        case (.bool, .bool), (.number, .number), (.string, .string): true
        default: false
        }
    }
}

extension DebugDrawerFeatureFlagValue: Codable {
    /// Decodes the bare JSON value: a Boolean, then a number, then a string.
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
    /// - Throws: The encoder's error.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .bool(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        }
    }
}

/// A feature flag a sidecar may see: its key and the value the app reads for it now.
public struct DebugDrawerFeatureFlag: Codable, Equatable, Sendable {
    /// Identifies the flag to the flag service ("new-checkout").
    public let key: String
    /// The value the app reads now, override included.
    public let value: DebugDrawerFeatureFlagValue

    /// A flag.
    ///
    /// - Parameters:
    ///   - key: Identifies the flag to the flag service.
    ///   - value: The value the app reads now, override included.
    public init(key: String, value: DebugDrawerFeatureFlagValue) {
        self.key = key
        self.value = value
    }
}
