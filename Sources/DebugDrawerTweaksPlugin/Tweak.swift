/// A setting the host declares for the drawer's Tweaks plugin, and the typed accessor the app
/// reads it with: a toggle, a picker, a text field or a stepper.
///
/// Declare each once, as a constant, and list it in a ``TweakSection``; read it through
/// ``value`` wherever the app needs it:
///
/// ```swift
/// enum AppTweaks {
///     static let newCheckout = Tweak.toggle("New checkout", key: "newCheckout", default: false)
/// }
///
/// if AppTweaks.newCheckout.value { ... }
/// ```
///
/// The type exists in every build. In release there is no drawer and nothing is stored, so
/// ``value`` is always ``defaultValue``.
public struct Tweak<Value: Sendable & Equatable>: Sendable {
    /// What the drawer shows beside the control ("New checkout").
    public let title: String
    /// Identifies the stored value; keep it when the title changes, or the stored value is lost.
    public let key: String
    /// The value until someone changes it, after a reset, and always in release.
    public let defaultValue: Value
    /// Whether the tweak may be offered outside debug builds. Set with ``productionSafe(_:)``.
    public private(set) var isProductionSafe = false

    let control: TweakControl
    private let encode: @Sendable (Value) -> TweakStoredValue
    private let decode: @Sendable (TweakStoredValue) -> Value?

    private init(
        title: String,
        key: String,
        defaultValue: Value,
        control: TweakControl,
        encode: @escaping @Sendable (Value) -> TweakStoredValue,
        decode: @escaping @Sendable (TweakStoredValue) -> Value?
    ) {
        self.title = title
        self.key = key
        self.defaultValue = defaultValue
        self.control = control
        self.encode = encode
        self.decode = decode
    }

    /// The same tweak, marked as safe (or, passing `false`, not safe) to offer outside debug
    /// builds, such as to a companion tool. The drawer shows it the same either way.
    public func productionSafe(_ isProductionSafe: Bool = true) -> Tweak {
        var tweak = self
        tweak.isProductionSafe = isProductionSafe
        return tweak
    }

    /// `value` as storage holds it.
    func storedValue(of value: Value) -> TweakStoredValue {
        encode(value)
    }

    /// The value `stored` holds, or the default when nothing is stored or what is stored isn't
    /// one of the tweak's values (a picker's removed option, a value of another type).
    func value(from stored: TweakStoredValue?) -> Value {
        stored.flatMap(decode) ?? defaultValue
    }
}

// MARK: - Declarations

public extension Tweak where Value == Bool {
    /// A switch.
    ///
    /// - Parameters:
    ///   - title: What the drawer shows beside the switch.
    ///   - key: Identifies the stored value.
    ///   - defaultValue: The value until someone flips the switch.
    static func toggle(_ title: String, key: String, default defaultValue: Bool) -> Tweak {
        Tweak(title: title, key: key, defaultValue: defaultValue, control: .toggle, encode: { .bool($0) }, decode: \.bool)
    }
}

public extension Tweak where Value == String {
    /// A text field. An empty string is a value of its own, distinct from the default.
    ///
    /// - Parameters:
    ///   - title: What the drawer shows beside the field.
    ///   - key: Identifies the stored value.
    ///   - defaultValue: The text until someone edits it.
    static func text(_ title: String, key: String, default defaultValue: String) -> Tweak {
        Tweak(title: title, key: key, defaultValue: defaultValue, control: .text, encode: { .string($0) }, decode: \.string)
    }

    /// A choice among strings, each shown as it is.
    ///
    /// - Parameters:
    ///   - title: What the drawer shows beside the picker.
    ///   - key: Identifies the stored value.
    ///   - options: The strings to choose among, in the order shown.
    ///   - defaultValue: The choice until someone picks another; one of `options`.
    /// - Precondition: `options` contains `defaultValue`. A stored string that is no longer one
    ///   of `options` reads as `defaultValue`.
    static func picker(_ title: String, key: String, options: [String], default defaultValue: String) -> Tweak {
        precondition(options.contains(defaultValue), "The default of picker tweak \(key) isn't one of its options")
        let choices = Set(options)
        return Tweak(
            title: title,
            key: key,
            defaultValue: defaultValue,
            control: .picker(options.map { TweakOption(title: $0, value: .string($0)) }),
            encode: { .string($0) },
            decode: { $0.string.flatMap { choices.contains($0) ? $0 : nil } }
        )
    }
}

public extension Tweak where Value == Int {
    /// A stepper over a range of integers.
    ///
    /// - Parameters:
    ///   - title: What the drawer shows beside the stepper.
    ///   - key: Identifies the stored value.
    ///   - defaultValue: The value until someone steps it; within `range`.
    ///   - range: The values the stepper reaches. A stored value outside it reads as the nearest
    ///     bound.
    ///   - step: How far one press moves the value.
    /// - Precondition: `range` contains `defaultValue`, and `step` is positive.
    static func stepper(_ title: String, key: String, default defaultValue: Int, in range: ClosedRange<Int>, step: Int = 1) -> Tweak {
        precondition(range.contains(defaultValue), "The default of stepper tweak \(key) is outside its range")
        precondition(step > 0, "The step of stepper tweak \(key) isn't positive")
        return Tweak(
            title: title,
            key: key,
            defaultValue: defaultValue,
            control: .stepper(range: range, step: step),
            encode: { .int($0) },
            decode: { $0.int.map { min(max($0, range.lowerBound), range.upperBound) } }
        )
    }
}

public extension Tweak where Value: CaseIterable & RawRepresentable, Value.RawValue == String {
    /// A choice among an enumeration's cases, each shown as `String(describing:)` shows it (its
    /// name, unless the type describes itself) and stored as its raw value.
    ///
    /// - Parameters:
    ///   - title: What the drawer shows beside the picker.
    ///   - key: Identifies the stored value.
    ///   - defaultValue: The case until someone picks another. A stored raw value that is no
    ///     longer a case reads as `defaultValue`.
    static func picker(_ title: String, key: String, default defaultValue: Value) -> Tweak {
        Tweak(
            title: title,
            key: key,
            defaultValue: defaultValue,
            control: .picker(Value.allCases.map { TweakOption(title: String(describing: $0), value: .string($0.rawValue)) }),
            encode: { .string($0.rawValue) },
            decode: { $0.string.flatMap(Value.init(rawValue:)) }
        )
    }
}

public extension Tweak where Value: CaseIterable & RawRepresentable, Value.RawValue == Int {
    /// A choice among an enumeration's cases, each shown as `String(describing:)` shows it (its
    /// name, unless the type describes itself) and stored as its raw value.
    ///
    /// - Parameters:
    ///   - title: What the drawer shows beside the picker.
    ///   - key: Identifies the stored value.
    ///   - defaultValue: The case until someone picks another. A stored raw value that is no
    ///     longer a case reads as `defaultValue`.
    static func picker(_ title: String, key: String, default defaultValue: Value) -> Tweak {
        Tweak(
            title: title,
            key: key,
            defaultValue: defaultValue,
            control: .picker(Value.allCases.map { TweakOption(title: String(describing: $0), value: .int($0.rawValue)) }),
            encode: { .int($0.rawValue) },
            decode: { $0.int.flatMap(Value.init(rawValue:)) }
        )
    }
}

// MARK: - Controls

/// How the drawer edits a tweak.
enum TweakControl: Hashable, Sendable {
    case toggle
    case picker([TweakOption])
    case text
    case stepper(range: ClosedRange<Int>, step: Int)
}

/// One of a picker's choices: what it shows and what it stores.
struct TweakOption: Hashable, Sendable {
    let title: String
    let value: TweakStoredValue
}
