import Foundation

/// A value a sidecar passes a scenario for one of its declared parameters: text (a choice's option
/// too), a whole number or a switch.
///
/// The receiver checks each against the parameter it is for (``DebugDrawerScenarioParameter``)
/// before the scenario's handler sees it; the handler reads it typed, through
/// ``DebugDrawerScenario/Arguments``.
public enum DebugDrawerScenarioValue: Codable, Equatable, Hashable, Sendable {
    /// Text: a string parameter's value, or one of a choice parameter's options.
    case string(String)
    /// A whole number.
    case integer(Int)
    /// On or off.
    case boolean(Bool)
}
