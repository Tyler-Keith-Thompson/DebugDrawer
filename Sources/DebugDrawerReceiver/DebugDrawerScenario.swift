import Foundation

/// A named state of the app a sidecar can launch it into ("open order 123", "show the paywall",
/// "onboarding step 3"): its ID, how a sidecar lists it, the parameters it takes, and the host's
/// handler that puts the app there.
///
/// ```swift
/// let openOrder = DebugDrawerScenario("open-order", title: "Open Order", parameters: [
///     .integer("orderID", title: "Order", default: 123, in: 1 ... 999_999)
/// ]) { arguments in
///     router.openOrder(arguments.integer("orderID") ?? 123)
/// }
/// receiver.enable(.scenarios([openOrder], launchURL: URL(string: "shop-internal://")))
/// ```
///
/// The handler is the host's code and runs on the main actor. It receives only the parameters the
/// scenario declares, each checked against its declaration, so it never sees anything else a
/// command carried.
public struct DebugDrawerScenario: Identifiable {
    /// The values a scenario's handler receives: one for each parameter the scenario declares, of
    /// the parameter's kind and within its bounds, the parameter's default where the command left
    /// it out.
    public struct Arguments: Equatable, Sendable {
        /// The values, by parameter name.
        public let values: [String: DebugDrawerScenarioValue]

        /// Arguments holding `values`.
        ///
        /// - Parameter values: The values, by parameter name.
        public init(_ values: [String: DebugDrawerScenarioValue]) {
            self.values = values
        }

        /// The value of the string or choice parameter `name`, or `nil` when the scenario declares
        /// no such parameter.
        ///
        /// - Parameter name: A parameter's name.
        /// - Returns: The text.
        public func string(_ name: String) -> String? {
            guard case let .string(text) = values[name] else { return nil }
            return text
        }

        /// The value of the integer parameter `name`, or `nil` when the scenario declares no such
        /// parameter.
        ///
        /// - Parameter name: A parameter's name.
        /// - Returns: The number.
        public func integer(_ name: String) -> Int? {
            guard case let .integer(number) = values[name] else { return nil }
            return number
        }

        /// The value of the boolean parameter `name`, or `nil` when the scenario declares no such
        /// parameter.
        ///
        /// - Parameter name: A parameter's name.
        /// - Returns: Whether it is on.
        public func boolean(_ name: String) -> Bool? {
            guard case let .boolean(isOn) = values[name] else { return nil }
            return isOn
        }
    }

    /// The ID a sidecar launches it by.
    public let id: String
    /// The name a sidecar lists it under.
    public let title: String
    /// What it does, as a sidecar shows it under the title; empty for none.
    public let summary: String
    /// The parameters it takes, in the order a sidecar shows their fields.
    public let parameters: [DebugDrawerScenarioParameter]
    /// Puts the app in the scenario's state.
    let handler: @MainActor (Arguments) -> Void

    /// A scenario.
    ///
    /// Traps when two parameters share a name.
    ///
    /// - Parameters:
    ///   - id: The ID a sidecar launches it by.
    ///   - title: The name a sidecar lists it under.
    ///   - summary: What it does, shown under the title.
    ///   - parameters: The parameters it takes; a command may pass these and no others.
    ///   - handler: The host's code that puts the app in the scenario's state, given the checked
    ///     values of the declared parameters. It runs on the main actor, once per launch.
    public init(
        _ id: String,
        title: String,
        summary: String = "",
        parameters: [DebugDrawerScenarioParameter] = [],
        handler: @escaping @MainActor (Arguments) -> Void
    ) {
        precondition(Set(parameters.map(\.name)).count == parameters.count, "Two parameters of the scenario \(id) share a name")
        self.id = id
        self.title = title
        self.summary = summary
        self.parameters = parameters
        self.handler = handler
    }

    /// The arguments for `values`, or `nil` when a command passing them is refused as
    /// ``DebugDrawerAuditEntry/Refusal/malformedCommand``: it names a parameter the scenario
    /// doesn't declare, or passes a value its parameter doesn't take. A declared parameter left out
    /// takes its default.
    func arguments(for values: [String: DebugDrawerScenarioValue]) -> Arguments? {
        let declared = Dictionary(uniqueKeysWithValues: parameters.map { ($0.name, $0) })
        for (name, value) in values {
            guard let parameter = declared[name], parameter.accepts(value) else { return nil }
        }
        return Arguments(Dictionary(uniqueKeysWithValues: parameters.map { ($0.name, values[$0.name] ?? $0.defaultValue) }))
    }
}
