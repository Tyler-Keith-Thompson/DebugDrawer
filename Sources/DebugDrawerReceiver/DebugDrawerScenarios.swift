import Combine
import Foundation
import os

// The scenario launcher's model. A scenario's handler is the host's code, so the receiver's part is
// to pass it nothing but a scenario ID the host registered and values for the parameters that
// scenario declared, each checked against its declaration: an ID the host didn't register is
// refused `notExposed` (as an unlisted flag is), a parameter it didn't declare or a value its
// parameter doesn't take `malformedCommand` (as a tweak's value outside its options is), both
// before the model sees the command (`refusal(of:)`). Nothing received is evaluated: the ID picks
// one of the host's closures, the values are data the closure reads.
//
// Running a scenario can't be undone by the library (the handler did whatever it does), so the
// capability is persistent rather than session-scoped, with no revert; the sessions still gate
// every command. The snapshot's `lastRun` lets a sidecar see that its launch landed, since the app
// may perform it only as it comes to the foreground.
//
// Rejected: reusing the Deep Link plugin's presets (a debug-only plugin a release build doesn't
// link, and a URL the app parses is input the handler would evaluate), and a scenario handler that
// receives the raw command (it could read anything the sidecar sent).

/// The model behind the scenario launcher ``DebugDrawerReceiverCapability``: the scenarios the host
/// registered, with their declared parameters, and the last one a sidecar launched.
///
/// A debug build can show the same model in its drawer, through
/// `DebugDrawerPluginTransport.direct(to:)`, while the receiver serves it.
@MainActor
public final class DebugDrawerScenarios: DebugDrawerPluginModel {
    private static let logger = Logger(subsystem: "DebugDrawerReceiver", category: "DebugDrawerScenarios")

    /// The ID the receiver serves it under.
    public static let pluginID = "DebugDrawer.Scenarios"

    /// A scenario as a sidecar lists it: everything but its handler.
    public struct Entry: Codable, Equatable, Sendable, Identifiable {
        /// The ID a sidecar launches it by.
        public let id: String
        /// The name a sidecar lists it under.
        public let title: String
        /// What it does; empty for none.
        public let summary: String
        /// The parameters it takes, in the order to show their fields.
        public let parameters: [DebugDrawerScenarioParameter]

        /// An entry.
        ///
        /// - Parameters:
        ///   - id: The ID a sidecar launches it by.
        ///   - title: The name a sidecar lists it under.
        ///   - summary: What it does.
        ///   - parameters: The parameters it takes.
        public init(id: String, title: String, summary: String, parameters: [DebugDrawerScenarioParameter]) {
            self.id = id
            self.title = title
            self.summary = summary
            self.parameters = parameters
        }
    }

    /// A scenario a sidecar launched.
    public struct Run: Codable, Equatable, Sendable {
        /// Counts the launches since the app started, from 1.
        public let number: Int
        /// The scenario's ID.
        public let scenario: String
        /// When its handler ran.
        public let date: Date

        /// A launch.
        ///
        /// - Parameters:
        ///   - number: Counts the launches since the app started, from 1.
        ///   - scenario: The scenario's ID.
        ///   - date: When its handler ran.
        public init(number: Int, scenario: String, date: Date) {
            self.number = number
            self.scenario = scenario
            self.date = date
        }
    }

    /// What a sidecar sees.
    public struct Snapshot: Codable, Equatable, Sendable {
        /// The scenarios the host registered, in its order.
        public var scenarios: [Entry]
        /// The URL a sidecar opens to bring the app to the foreground (its URL scheme), or `nil`
        /// when the host declares none; a Mac sidecar opens the app by its bundle identifier.
        public var launchURL: URL?
        /// The last scenario a sidecar launched since the app started, or `nil`.
        public var lastRun: Run?

        /// A snapshot.
        ///
        /// - Parameters:
        ///   - scenarios: The scenarios the host registered.
        ///   - launchURL: The URL a sidecar opens to bring the app to the foreground.
        ///   - lastRun: The last scenario a sidecar launched.
        public init(scenarios: [Entry], launchURL: URL?, lastRun: Run?) {
            self.scenarios = scenarios
            self.launchURL = launchURL
            self.lastRun = lastRun
        }
    }

    /// What a sidecar asks.
    public enum Command: Codable, Equatable, Sendable {
        /// Runs the handler of the scenario `scenario` with `arguments`, values for parameters the
        /// scenario declares; one it leaves out takes its default.
        case run(scenario: String, arguments: [String: DebugDrawerScenarioValue])
    }

    /// The scenarios and the last launch now.
    @Published public private(set) var snapshot: Snapshot

    private let scenarios: [String: DebugDrawerScenario]
    private let now: () -> Date

    /// The scenarios `scenarios`, launched from a sidecar that opens the app with `launchURL`.
    ///
    /// Traps when two scenarios share an ID.
    ///
    /// - Parameters:
    ///   - scenarios: The scenarios a sidecar may launch, in the order to list them.
    ///   - launchURL: A URL of the app's own scheme that brings it to the foreground (on iOS the
    ///     only way a sidecar can); `nil` when it has none. The receiver doesn't need it: a command
    ///     the sidecar leaves is performed as the app comes to the foreground however it got there.
    public convenience init(scenarios: [DebugDrawerScenario], launchURL: URL? = nil) {
        self.init(scenarios: scenarios, launchURL: launchURL, now: Date.init)
    }

    /// The scenarios `scenarios`, timing launches with `now`.
    package init(scenarios: [DebugDrawerScenario], launchURL: URL?, now: @escaping () -> Date) {
        precondition(Set(scenarios.map(\.id)).count == scenarios.count, "Two scenarios share an ID")
        self.scenarios = Dictionary(uniqueKeysWithValues: scenarios.map { ($0.id, $0) })
        self.now = now
        snapshot = Snapshot(
            scenarios: scenarios.map { Entry(id: $0.id, title: $0.title, summary: $0.summary, parameters: $0.parameters) },
            launchURL: launchURL,
            lastRun: nil
        )
    }

    /// Why the receiver refuses `command` before the model performs it, or `nil` to perform it: a
    /// scenario the host didn't register is ``DebugDrawerAuditEntry/Refusal/notExposed``; a
    /// parameter it doesn't declare, or a value its parameter doesn't take,
    /// ``DebugDrawerAuditEntry/Refusal/malformedCommand``.
    func refusal(of command: Command) -> DebugDrawerAuditEntry.Refusal? {
        switch command {
        case let .run(id, values):
            guard let scenario = scenarios[id] else { return .notExposed }
            return scenario.arguments(for: values) == nil ? .malformedCommand : nil
        }
    }

    /// Runs the scenario `command` names with its checked arguments; does nothing for a scenario
    /// the host didn't register or arguments its parameters don't take.
    ///
    /// - Parameter command: What to do.
    public func perform(_ command: Command) {
        switch command {
        case let .run(id, values):
            guard let scenario = scenarios[id] else {
                Self.logger.notice("Ignored a scenario the host didn't register")
                return
            }
            guard let arguments = scenario.arguments(for: values) else {
                Self.logger.notice("Ignored a scenario's arguments its parameters don't take")
                return
            }
            scenario.handler(arguments)
            snapshot.lastRun = Run(number: (snapshot.lastRun?.number ?? 0) + 1, scenario: id, date: now())
        }
    }
}
