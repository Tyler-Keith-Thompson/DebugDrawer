import Foundation

// A scenario's parameter is declared by the host with its kind and its bounds, so the receiver can
// check a sidecar's value against it without asking the host: a string no longer than its maximum,
// an integer within its range, a switch, or one of a closed list of options. The kinds are the ones
// a sidecar can draw as a field without knowing the host (text field, number field, toggle,
// picker). Rejected: a free-form JSON value (the handler would parse input the receiver never
// checked) and a validation closure (it would run on received input before the handler, and a
// sidecar couldn't show the bounds). A declaration that contradicts itself (a default outside the
// bounds, no options) is refused by the scenarios it is handed to
// (`DebugDrawerScenarios.InvalidScenarios`) rather than by each factory, so a scenario's list of
// parameters reads without a `try` per parameter and one `catch` covers every declaration.

/// A named, typed parameter a ``DebugDrawerScenario`` declares: the only values a sidecar may pass
/// the scenario.
///
/// ```swift
/// DebugDrawerScenario("open-order", title: "Open Order", parameters: [
///     .integer("orderID", title: "Order", default: 123, in: 1 ... 999_999)
/// ]) { arguments in
///     router.openOrder(arguments.integer("orderID") ?? 123)
/// }
/// ```
///
/// A sidecar reads the declaration in the scenarios' snapshot and draws a field for it; the
/// receiver refuses a command whose value for it isn't of its kind or is outside its bounds, as
/// ``DebugDrawerAuditEntry/Refusal/malformedCommand``.
public struct DebugDrawerScenarioParameter: Codable, Equatable, Sendable {
    /// What a parameter takes.
    public enum Kind: Codable, Equatable, Sendable {
        /// Text of at most `maximumLength` characters.
        case string(maximumLength: Int)
        /// A whole number within `range`.
        case integer(range: ClosedRange<Int>)
        /// On or off.
        case boolean
        /// One of `options`, passed as a ``DebugDrawerScenarioValue/string(_:)``.
        case choice(options: [String])
    }

    /// The name the handler reads the value by, and a command passes it under.
    public let name: String
    /// The name a sidecar shows beside the field.
    public let title: String
    /// What the parameter takes.
    public let kind: Kind
    /// The value a sidecar starts the field at, and the handler gets when a command leaves the
    /// parameter out.
    public let defaultValue: DebugDrawerScenarioValue

    /// A text parameter.
    ///
    /// - Parameters:
    ///   - name: The name the handler reads the value by.
    ///   - title: The name a sidecar shows; `name` when `nil`.
    ///   - default: The value a sidecar starts at; no longer than `maximumLength`, or the scenarios
    ///     throw.
    ///   - maximumLength: The most characters a value may have; positive, or the scenarios throw.
    /// - Returns: The parameter.
    public static func string(_ name: String, title: String? = nil, default: String = "", maximumLength: Int = 256) -> Self {
        Self(name: name, title: title ?? name, kind: .string(maximumLength: maximumLength), defaultValue: .string(`default`))
    }

    /// A whole-number parameter.
    ///
    /// - Parameters:
    ///   - name: The name the handler reads the value by.
    ///   - title: The name a sidecar shows; `name` when `nil`.
    ///   - default: The value a sidecar starts at; within `range`, or the scenarios throw.
    ///   - range: The values it takes.
    /// - Returns: The parameter.
    public static func integer(_ name: String, title: String? = nil, default: Int = 0, in range: ClosedRange<Int> = Int.min ... Int.max) -> Self {
        Self(name: name, title: title ?? name, kind: .integer(range: range), defaultValue: .integer(`default`))
    }

    /// An on-or-off parameter.
    ///
    /// - Parameters:
    ///   - name: The name the handler reads the value by.
    ///   - title: The name a sidecar shows; `name` when `nil`.
    ///   - default: The value a sidecar starts at.
    /// - Returns: The parameter.
    public static func boolean(_ name: String, title: String? = nil, default: Bool = false) -> Self {
        Self(name: name, title: title ?? name, kind: .boolean, defaultValue: .boolean(`default`))
    }

    /// A parameter taking one of `options`.
    ///
    /// - Parameters:
    ///   - name: The name the handler reads the value by.
    ///   - title: The name a sidecar shows; `name` when `nil`.
    ///   - options: The values it takes, in the order a sidecar lists them; at least one and none
    ///     repeated, or the scenarios throw.
    ///   - default: The value a sidecar starts at, one of `options` or the scenarios throw; the
    ///     first option when `nil`.
    /// - Returns: The parameter.
    public static func choice(_ name: String, title: String? = nil, options: [String], default: String? = nil) -> Self {
        // With no options the default is empty text, which the scenarios refuse as `noOptions`.
        let initial = `default` ?? options.first ?? ""
        return Self(name: name, title: title ?? name, kind: .choice(options: options), defaultValue: .string(initial))
    }

    /// Whether the parameter takes `value`: of its kind and within its bounds.
    ///
    /// - Parameter value: A value a sidecar passed.
    /// - Returns: `true` when the handler may receive it.
    public func accepts(_ value: DebugDrawerScenarioValue) -> Bool {
        switch (kind, value) {
        case let (.string(maximumLength), .string(text)): text.count <= maximumLength
        case let (.integer(range), .integer(number)): range.contains(number)
        case (.boolean, .boolean): true
        case let (.choice(options), .string(option)): options.contains(option)
        default: false
        }
    }
}

extension DebugDrawerScenarioParameter {
    /// Throws when the declaration contradicts itself: a string's maximum length not positive or
    /// its default longer, an integer's default outside its range, a choice with no options, a
    /// repeated one or a default not among them.
    func check() throws(DebugDrawerScenarios.InvalidScenarios) {
        switch kind {
        case let .string(maximumLength):
            guard maximumLength > 0 else { throw .maximumLengthNotPositive }
            guard accepts(defaultValue) else { throw .defaultTooLong }
        case .integer:
            guard accepts(defaultValue) else { throw .defaultOutOfRange }
        case let .choice(options):
            guard !options.isEmpty else { throw .noOptions }
            guard Set(options).count == options.count else { throw .repeatedOption }
            guard accepts(defaultValue) else { throw .defaultNotAnOption }
        case .boolean:
            return
        }
    }
}
