import Combine
import Foundation
import os

// The environment switching capability's model (DD-120, charter D9: high risk). A leaked sidecar
// must not be able to point the app at a host of an attacker's, so the allowlist is the only thing
// a sidecar can pick from and it can't be left out: the initializer takes a default and at least
// one allowed environment as separate parameters (`allowing first:, _ rest...`), so an empty
// allowlist doesn't compile, and an environment with an empty ID or repeating another's ID (the
// default's included, which would leave nothing to switch to) throws `InvalidEnvironments`. The
// check is the model's rather than `DebugDrawerEnvironment`'s, so a list of environments reads
// without a `try` per value and one `catch` covers the allowlist. A command carries an environment's ID
// and nothing else; one the host didn't list is refused `notExposed` before the model sees it, and
// the adapter is handed the host's own value, never a decoded one. Nothing in the model, its
// snapshot or its commands can hold a URL.
//
// The switch lasts for the session, always (no scope parameter): a backend left switched past the
// session would send an employee's real use to staging. The environment a session switched to is
// written to the defaults before the adapter is told, so a launch that follows a kill finds it and
// puts the default back as the capability is made.
//
// Rejected: an allowlist as an array (an empty one would be an error at run time instead of a
// compile error, and an allowlist built from remote configuration is the very thing a leak would target:
// it belongs in the app's source); a variant taking an array for config-driven lists, for the same
// reason; and `requiringGrant()` built in, as network mocking has it (charter D6 keeps grants
// optional, and with a grant policy every capability already needs a grant listing it, so where a
// verifier is configured a switch is refused without one; a host that wants a grant even without
// a policy adds `.requiringGrant()`).

/// The model behind the environment switching ``DebugDrawerReceiverCapability``: the host's
/// default environment, those it allows a sidecar to switch to, and which is active.
///
/// A debug build can show the same model in its drawer, through
/// `DebugDrawerPluginTransport.direct(to:)`, while the receiver serves it.
@MainActor
public final class DebugDrawerEnvironments: DebugDrawerPluginModel {
    private static let logger = Logger(subsystem: "DebugDrawerReceiver", category: "DebugDrawerEnvironments")

    /// The ID the receiver serves it under.
    public static let pluginID = "DebugDrawer.Environments"

    /// What a sidecar sees: the environments by ID, title and summary, and which is active. No
    /// field holds a URL.
    public struct Snapshot: Codable, Equatable, Sendable {
        /// The environments a sidecar may pick, the default first, then the allowed ones in the
        /// host's order.
        public var environments: [DebugDrawerEnvironment]
        /// The ID of the environment the app starts in and returns to as the session ends.
        public var defaultEnvironment: String
        /// The ID of the environment the app is pointed at now.
        public var activeEnvironment: String

        /// Whether the app is pointed at another environment than its default: show the host's
        /// session indicator, naming it, while it is.
        public var isSwitched: Bool {
            activeEnvironment != defaultEnvironment
        }

        /// A snapshot.
        ///
        /// - Parameters:
        ///   - environments: The environments a sidecar may pick, the default first.
        ///   - defaultEnvironment: The ID of the environment the app starts in.
        ///   - activeEnvironment: The ID of the environment the app is pointed at now.
        public init(environments: [DebugDrawerEnvironment], defaultEnvironment: String, activeEnvironment: String) {
            self.environments = environments
            self.defaultEnvironment = defaultEnvironment
            self.activeEnvironment = activeEnvironment
        }
    }

    /// What a sidecar asks.
    public enum Command: Codable, Equatable, Sendable {
        /// Points the app at the environment whose ID is `environment`: one the host listed.
        case activate(environment: String)
        /// Points the app back at its default environment: the session's revert.
        case reset
    }

    /// An allowlist the model can't serve, which it refuses as it is made.
    public enum InvalidEnvironments: Error, Equatable, Sendable {
        /// An environment's ID is empty.
        case emptyID
        /// Two environments, the default included, share an ID.
        case duplicateID
    }

    /// The environments and the active one now.
    @Published public private(set) var snapshot: Snapshot

    /// The defaults key under which the model keeps the environment a session switched to.
    nonisolated static let activeEnvironmentDefaultsKey = "DebugDrawer.Environments.activeEnvironment"

    private let defaultEnvironment: DebugDrawerEnvironment
    private let environments: [String: DebugDrawerEnvironment]
    private let adapter: any DebugDrawerEnvironmentAdapter
    private let defaults: UserDefaults

    /// The host's environments: `defaultEnvironment`, the one the app starts in, and those a
    /// sidecar may switch it to, at least one, switched through `adapter`.
    ///
    /// - Parameters:
    ///   - defaultEnvironment: The environment the app starts in and returns to as each session
    ///     ends: usually production.
    ///   - first: An environment a sidecar may switch the app to.
    ///   - rest: More environments a sidecar may switch the app to, in the order to list them.
    ///   - adapter: The host's adapter, which maps each environment's ID to its own configuration.
    ///   - defaults: Where the model keeps the ID of the environment a session switched to, so a
    ///     launch that follows a kill puts the default back; never anything of the configuration.
    /// - Throws: ``InvalidEnvironments/emptyID`` when an environment's ID is empty, and
    ///   ``InvalidEnvironments/duplicateID`` when two environments, the default included, share
    ///   an ID.
    public convenience init(
        default defaultEnvironment: DebugDrawerEnvironment,
        allowing first: DebugDrawerEnvironment,
        _ rest: DebugDrawerEnvironment...,
        adapter: some DebugDrawerEnvironmentAdapter,
        defaults: UserDefaults = .standard
    ) throws(InvalidEnvironments) {
        try self.init(default: defaultEnvironment, allowing: first, rest, adapter: adapter, defaults: defaults)
    }

    /// The host's environments, the allowed ones after `first` as a list, for the capability's
    /// variadic factory, which can't forward its own.
    ///
    /// - Throws: As ``init(default:allowing:_:adapter:defaults:)`` does.
    init(
        default defaultEnvironment: DebugDrawerEnvironment,
        allowing first: DebugDrawerEnvironment,
        _ rest: [DebugDrawerEnvironment],
        adapter: any DebugDrawerEnvironmentAdapter,
        defaults: UserDefaults
    ) throws(InvalidEnvironments) {
        let listed = [defaultEnvironment, first] + rest
        guard !listed.contains(where: \.id.isEmpty) else { throw .emptyID }
        guard Set(listed.map(\.id)).count == listed.count else { throw .duplicateID }
        self.defaultEnvironment = defaultEnvironment
        environments = Dictionary(uniqueKeysWithValues: listed.map { ($0.id, $0) })
        self.adapter = adapter
        self.defaults = defaults
        snapshot = Snapshot(
            environments: listed,
            defaultEnvironment: defaultEnvironment.id,
            activeEnvironment: defaults.string(forKey: Self.activeEnvironmentDefaultsKey) ?? defaultEnvironment.id
        )
    }

    /// Why the receiver refuses `command` before the model performs it, or `nil` to perform it: an
    /// environment the host didn't list is ``DebugDrawerAuditEntry/Refusal/notExposed``.
    func refusal(of command: Command) -> DebugDrawerAuditEntry.Refusal? {
        switch command {
        case let .activate(id):
            environments[id] == nil ? .notExposed : nil
        case .reset:
            nil
        }
    }

    /// Does what `command` asks, for an environment the host listed only.
    ///
    /// - Parameter command: What to do.
    public func perform(_ command: Command) {
        switch command {
        case let .activate(id):
            guard let environment = environments[id] else {
                Self.logger.notice("Ignored an environment the host didn't list")
                return
            }
            activate(environment)
        case .reset:
            activate(defaultEnvironment)
        }
    }

    private func activate(_ environment: DebugDrawerEnvironment) {
        guard environment.id != snapshot.activeEnvironment else { return }
        // Recorded before the adapter switches, so a kill between the two still leaves the record
        // the next launch reverts from.
        if environment.id == defaultEnvironment.id {
            adapter.activate(environment)
            defaults.removeObject(forKey: Self.activeEnvironmentDefaultsKey)
        } else {
            defaults.set(environment.id, forKey: Self.activeEnvironmentDefaultsKey)
            adapter.activate(environment)
        }
        snapshot.activeEnvironment = environment.id
    }
}
