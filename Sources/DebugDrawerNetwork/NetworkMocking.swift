import Combine
import DebugDrawerReceiver
import Foundation
import os

// The network-mocking capability's model. It follows the receiver's sessions itself, as the
// analytics mirror does: a session opening starts with no rules, and its end or expiry takes every
// rule out of effect, so rules never outlive the session that set them. The receiver also reverts
// it with `reset` as the session ends, as it does any session-scoped capability; following the
// sessions covers the time between the expiry date and the system's timer, as the URL protocol
// checks the expiry at each request. Rejected: rules kept across sessions or launches (a mock left
// on would answer the next person's requests with nothing saying why), and the rules in effect
// whenever set, session or not (a debug-build drawer driving the model in the process would answer
// requests no session allowed).

/// Mock responses and conditioning for a production build, set from a sidecar during its session:
/// the requests the app sends through a session that lists ``NetworkMockingURLProtocol``, to a
/// host the app allows, are answered from the sidecar's ``NetworkMockRule``s, until the session
/// ends.
///
/// The host makes it with the hosts a sidecar may mock, enables the capability, and lists the URL
/// protocol in the configuration of each `URLSession` whose requests may be mocked:
///
/// ```swift
/// let mocking = NetworkMocking(sessions: sessions, allowedHosts: [.domain("staging.example.com")])
/// receiver.enable(.networkMocking(mocking))
///
/// let configuration = URLSessionConfiguration.default
/// configuration.protocolClasses = [NetworkMockingURLProtocol.self] + (configuration.protocolClasses ?? [])
/// let session = URLSession(configuration: configuration)
/// ```
///
/// A sidecar connects to ``pluginID`` with ``Snapshot`` and ``Command``. Outside a session, and in
/// an app that hasn't enabled it, every command is refused, and no request is touched. Show
/// ``Snapshot/isActive`` in the app's session indicator.
@MainActor
public final class NetworkMocking: DebugDrawerPluginModel {
    private static let logger = Logger(subsystem: "DebugDrawerNetwork", category: "NetworkMocking")

    /// The ID the receiver serves it under.
    public static let pluginID = "DebugDrawer.NetworkMocking"

    /// What a sidecar sees.
    public struct Snapshot: Codable, Equatable, Sendable {
        /// The open session's ID, or `nil` while none is open.
        public var sessionID: UUID?
        /// The hosts the app allows rules to answer for.
        public var allowedHosts: [AllowedHost]
        /// The session's rules, in the order they are tried.
        public var rules: [NetworkMockRule]
        /// The session's conditioning profiles, in the order they are tried.
        public var conditions: [NetworkConditionProfile]

        /// Whether requests may be answered from the rules now: a session is open, the app allows
        /// at least one host, and at least one rule is on. Show it in the app's session indicator,
        /// as "Network mocking active".
        public var isActive: Bool {
            sessionID != nil && !allowedHosts.isEmpty && rules.contains(where: \.isEnabled)
        }

        /// A snapshot.
        ///
        /// - Parameters:
        ///   - sessionID: The open session's ID, or `nil`.
        ///   - allowedHosts: The hosts the app allows.
        ///   - rules: The session's rules.
        ///   - conditions: The session's conditioning profiles.
        public init(sessionID: UUID?, allowedHosts: [AllowedHost], rules: [NetworkMockRule], conditions: [NetworkConditionProfile]) {
            self.sessionID = sessionID
            self.allowedHosts = allowedHosts
            self.rules = rules
            self.conditions = conditions
        }
    }

    /// What a sidecar asks.
    ///
    /// The capability refuses, as `DebugDrawerAuditEntry.Refusal.malformedCommand`, a rule whose
    /// body is a file (the sidecar can't place one in the app's storage) and any host or path
    /// pattern that is a regular expression (no received expression is evaluated in the app); use
    /// an exact or wildcard pattern.
    public enum Command: Codable, Equatable, Sendable {
        /// Answers from `rules` from now on, in place of the session's earlier ones: the first rule
        /// that is on and matches a request to an allowed host answers it.
        case setRules([NetworkMockRule])
        /// Conditions the answers by `profiles` from now on, in place of the earlier ones: the
        /// first profile that is on and matches the request's host delays, paces or fails the
        /// rule's answer.
        case setConditions([NetworkConditionProfile])
        /// Removes every rule and profile; what the session's end performs.
        case reset
    }

    /// The session's rules and profiles now.
    @Published public private(set) var snapshot: Snapshot

    /// The hosts the app allows rules to answer for. A request to any other host is never
    /// touched; with none, nothing is.
    public nonisolated let allowedHosts: [AllowedHost]

    private nonisolated let route: NetworkMockingRoute
    private let scheduler: any NetworkConditionScheduler
    private let random: any NetworkConditionRandomSource
    private let now: @Sendable () -> Date
    /// When the open session expires, as the sessions last said.
    private var expires: Date?
    private var sessionObservation: AnyCancellable?

    /// Mocking that follows `sessions`' open session, for requests to `allowedHosts` alone.
    ///
    /// - Parameters:
    ///   - sessions: The receiver's sessions.
    ///   - allowedHosts: The hosts a sidecar's rules may answer for; empty allows none.
    public convenience init(sessions: DebugDrawerSessions, allowedHosts: [AllowedHost]) {
        self.init(
            sessions: sessions,
            allowedHosts: allowedHosts,
            scheduler: _NetworkConditionScheduler(),
            random: _NetworkConditionRandomSource(),
            now: { Date() },
            route: .shared
        )
    }

    /// Mocking with the services it times, rolls and dates by.
    ///
    /// - Parameters:
    ///   - sessions: The receiver's sessions.
    ///   - allowedHosts: The hosts a sidecar's rules may answer for.
    ///   - scheduler: What times latency and bandwidth.
    ///   - random: What decides which requests fail.
    ///   - now: The time a request is checked against the session's expiry at.
    ///   - route: Where the URL protocol finds the rules in effect.
    package init(
        sessions: DebugDrawerSessions,
        allowedHosts: [AllowedHost],
        scheduler: any NetworkConditionScheduler,
        random: any NetworkConditionRandomSource,
        now: @escaping @Sendable () -> Date,
        route: NetworkMockingRoute
    ) {
        self.allowedHosts = allowedHosts
        self.scheduler = scheduler
        self.random = random
        self.now = now
        self.route = route
        snapshot = Snapshot(sessionID: nil, allowedHosts: allowedHosts, rules: [], conditions: [])
        // The sessions are main-actor isolated and publish from there.
        sessionObservation = sessions.$snapshot.sink { [weak self] state in
            MainActor.assumeIsolated {
                self?.follow(state)
            }
        }
    }

    deinit {
        route.deactivate(ObjectIdentifier(self))
    }

    /// Does what `command` asks. Rules and profiles answer requests only while a session is open.
    ///
    /// - Parameter command: What to do.
    public func perform(_ command: Command) {
        switch command {
        case let .setRules(rules):
            snapshot.rules = rules
            Self.logger.notice("Network mocking has \(rules.count, privacy: .public) rules")
        case let .setConditions(profiles):
            snapshot.conditions = profiles
            Self.logger.notice("Network mocking has \(profiles.count, privacy: .public) conditioning profiles")
        case .reset:
            guard !snapshot.rules.isEmpty || !snapshot.conditions.isEmpty else { return }
            snapshot.rules = []
            snapshot.conditions = []
            Self.logger.notice("Network mocking was reset")
        }
        updateRoute()
    }

    /// Why the capability refuses `command`, or `nil` to perform it: a rule with a file body, or a
    /// regular expression anywhere, is malformed.
    package static func refusal(for command: Command) -> DebugDrawerAuditEntry.Refusal? {
        switch command {
        case let .setRules(rules):
            rules.allSatisfy(\.isAcceptedFromSidecar) ? nil : .malformedCommand
        case let .setConditions(profiles):
            profiles.contains { $0.host.isRegularExpression } ? .malformedCommand : nil
        case .reset:
            nil
        }
    }

    /// Starts a session with no rules as it opens, and takes them out of effect as it ends or
    /// expires.
    private func follow(_ state: DebugDrawerSessionState) {
        expires = state.session?.expires
        if state.session?.id != snapshot.sessionID {
            snapshot = Snapshot(sessionID: state.session?.id, allowedHosts: allowedHosts, rules: [], conditions: [])
        }
        updateRoute()
    }

    /// Puts the session's rules in effect for the URL protocol, or takes them out when there is no
    /// session or nothing to answer with.
    private func updateRoute() {
        let owner = ObjectIdentifier(self)
        guard snapshot.isActive, let expires else {
            route.deactivate(owner)
            return
        }
        route.activate(
            ActiveNetworkMocks(
                rules: snapshot.rules,
                conditions: snapshot.conditions,
                allowedHosts: allowedHosts,
                expires: expires,
                now: now,
                scheduler: scheduler,
                random: random
            ),
            for: owner
        )
    }
}

extension NetworkMockRule {
    /// Whether a sidecar may set the rule: its body isn't a file and no pattern is a regex.
    fileprivate var isAcceptedFromSidecar: Bool {
        if case .file = response.body {
            return false
        }
        return !matcher.host.isRegularExpression && !matcher.path.isRegularExpression
    }
}

extension NetworkMockRule.Pattern {
    /// Whether the pattern is a regular expression.
    fileprivate var isRegularExpression: Bool {
        if case .regex = self {
            return true
        }
        return false
    }
}
