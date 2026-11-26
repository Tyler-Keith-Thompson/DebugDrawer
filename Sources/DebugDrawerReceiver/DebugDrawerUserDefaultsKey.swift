import Foundation

// One entry of the allowlisted UserDefaults capability's allowlist (DD-127): a key the host lets a
// sidecar read and edit, declared with its kind and bounds, as a scenario's parameter is, so the
// receiver checks a sidecar's value without asking the host and a sidecar can draw the editor from
// the declaration alone. The kinds are the ones a sidecar can draw without knowing the host (text
// field, number field, toggle, picker). A key is read as its declared kind only: a value of
// another kind under it reads as none, so a key the host declared as a string never hands a
// sidecar the data blob something else wrote there. A declaration that contradicts itself (no
// options, a bound that isn't finite) or names one of the library's own keys is refused by the
// allowlist it is handed to (`DebugDrawerUserDefaults.InvalidKeys`) rather than by each factory,
// so a list of keys reads without a `try` per key and one `catch` covers the whole allowlist.
// Rejected: a validation closure (it would run on received input, and a sidecar couldn't show the
// bounds), and a key prefix or pattern (an allowlist must name each key: a pattern lets a key the
// host adds later through, unreviewed).

/// A UserDefaults key the host allowlists for a sidecar to read and edit, with the kind of value
/// it holds and the values a sidecar may write.
///
/// ```swift
/// try receiver.enable(.userDefaults(
///     .choice("plan", title: "Plan", options: ["free", "pro"]),
///     .bool("showsTips", title: "Shows Tips"),
///     .integer("itemsPerPage", title: "Items per Page", in: 10 ... 100)
/// ))
/// ```
///
/// A sidecar reads each key's value as its declared kind; the receiver refuses a value that isn't
/// of that kind or is outside its bounds as ``DebugDrawerAuditEntry/Refusal/malformedCommand``.
/// Never allowlist a key holding a secret: its value is shown to the sidecar and written to the
/// audit log with each edit. The allowlist, ``DebugDrawerUserDefaults``, throws
/// ``DebugDrawerUserDefaults/InvalidKeys`` as it is made for a key that contradicts itself or is
/// one of DebugDrawer's own.
public struct DebugDrawerUserDefaultsKey: Codable, Equatable, Sendable {
    /// The values a key holds.
    public enum Kind: Codable, Equatable, Sendable {
        /// Text of at most `maximumLength` characters.
        case string(maximumLength: Int)
        /// A whole number within `range`.
        case integer(range: ClosedRange<Int>)
        /// A finite number within `range`.
        case double(range: ClosedRange<Double>)
        /// On or off.
        case bool
        /// One of `options`, stored as a string.
        case choice(options: [String])

        /// Whether a sidecar may write `value` to a key of this kind: of the kind and within its
        /// bounds.
        ///
        /// - Parameter value: A value a sidecar sent.
        /// - Returns: `true` when the receiver writes it.
        public func accepts(_ value: DebugDrawerUserDefaultsValue) -> Bool {
            switch (self, value) {
            case let (.string(maximumLength), .string(text)): text.count <= maximumLength
            case let (.integer(range), .integer(number)): range.contains(number)
            case let (.double(range), .double(number)): number.isFinite && range.contains(number)
            case (.bool, .bool): true
            case let (.choice(options), .string(option)): options.contains(option)
            default: false
            }
        }

        /// What `object`, a value read from UserDefaults, is as this kind, or `nil` when it isn't
        /// one: a key never hands over a value of another kind.
        func value(of object: Any?) -> DebugDrawerUserDefaultsValue? {
            switch self {
            case .string, .choice:
                (object as? String).map(DebugDrawerUserDefaultsValue.string)
            case .integer:
                // An NSNumber holding a fraction doesn't bridge to Int, so 2.5 reads as none.
                (object as? Int).map(DebugDrawerUserDefaultsValue.integer)
            case .double:
                // JSON has no infinity or NaN, so a key holding one reads as none rather than
                // stopping the snapshot from encoding.
                (object as? Double).flatMap { $0.isFinite ? DebugDrawerUserDefaultsValue.double($0) : nil }
            case .bool:
                (object as? Bool).map(DebugDrawerUserDefaultsValue.bool)
            }
        }
    }

    /// The UserDefaults key.
    public let key: String
    /// The name a sidecar shows beside the editor.
    public let title: String
    /// The values it holds.
    public let kind: Kind

    private init(key: String, title: String?, kind: Kind) {
        self.key = key
        self.title = title ?? key
        self.kind = kind
    }

    /// A text key.
    ///
    /// - Parameters:
    ///   - key: The UserDefaults key; not empty or one of DebugDrawer's own (prefixed
    ///     `DebugDrawer.` or `com.debugdrawer.`), or the allowlist throws.
    ///   - title: The name a sidecar shows; `key` when `nil`.
    ///   - maximumLength: The most characters a sidecar may write; positive, or the allowlist
    ///     throws.
    /// - Returns: The key.
    public static func string(_ key: String, title: String? = nil, maximumLength: Int = 256) -> Self {
        Self(key: key, title: title, kind: .string(maximumLength: maximumLength))
    }

    /// A whole-number key.
    ///
    /// - Parameters:
    ///   - key: The UserDefaults key; not empty or one of DebugDrawer's own, or the allowlist
    ///     throws.
    ///   - title: The name a sidecar shows; `key` when `nil`.
    ///   - range: The values a sidecar may write.
    /// - Returns: The key.
    public static func integer(_ key: String, title: String? = nil, in range: ClosedRange<Int> = Int.min ... Int.max) -> Self {
        Self(key: key, title: title, kind: .integer(range: range))
    }

    /// A number key.
    ///
    /// - Parameters:
    ///   - key: The UserDefaults key; not empty or one of DebugDrawer's own, or the allowlist
    ///     throws.
    ///   - title: The name a sidecar shows; `key` when `nil`.
    ///   - range: The values a sidecar may write; finite bounds only, or the allowlist throws.
    /// - Returns: The key.
    public static func double(
        _ key: String,
        title: String? = nil,
        in range: ClosedRange<Double> = -Double.greatestFiniteMagnitude ... Double.greatestFiniteMagnitude
    ) -> Self {
        Self(key: key, title: title, kind: .double(range: range))
    }

    /// An on-or-off key.
    ///
    /// - Parameters:
    ///   - key: The UserDefaults key; not empty or one of DebugDrawer's own, or the allowlist
    ///     throws.
    ///   - title: The name a sidecar shows; `key` when `nil`.
    /// - Returns: The key.
    public static func bool(_ key: String, title: String? = nil) -> Self {
        Self(key: key, title: title, kind: .bool)
    }

    /// A key holding one of `options`, stored as a string.
    ///
    /// - Parameters:
    ///   - key: The UserDefaults key; not empty or one of DebugDrawer's own, or the allowlist
    ///     throws.
    ///   - title: The name a sidecar shows; `key` when `nil`.
    ///   - options: The values a sidecar may write, in the order it lists them; at least one and
    ///     none repeated, or the allowlist throws.
    /// - Returns: The key.
    public static func choice(_ key: String, title: String? = nil, options: [String]) -> Self {
        Self(key: key, title: title, kind: .choice(options: options))
    }
}

extension DebugDrawerUserDefaultsKey {
    /// Throws when the key is empty or one of DebugDrawer's own, or its kind contradicts itself.
    func check() throws(DebugDrawerUserDefaults.InvalidKeys) {
        guard !key.isEmpty else { throw .emptyKey }
        guard !key.hasPrefix("DebugDrawer."), !key.hasPrefix("com.debugdrawer.") else { throw .reservedKey }
        switch kind {
        case let .string(maximumLength):
            guard maximumLength > 0 else { throw .maximumLengthNotPositive }
        case let .double(range):
            // JSON has no infinity, so a bound that isn't finite couldn't reach a sidecar.
            guard range.lowerBound.isFinite, range.upperBound.isFinite else { throw .boundNotFinite }
        case let .choice(options):
            guard !options.isEmpty else { throw .noOptions }
            guard Set(options).count == options.count else { throw .repeatedOption }
        case .integer, .bool:
            return
        }
    }
}
