import Foundation
import os

// URL loading makes `NetworkMockingURLProtocol` by its class, from the configuration the host
// listed it in, so the protocol can't be handed the model that holds the rules; it reads them
// here. Only a model with a session open and rules on is listed, so outside a session the protocol
// claims nothing and every request goes on to the system's protocols untouched. The rules sit
// behind a lock rather than in an actor: URL loading asks from its own threads, synchronously.
// `OSAllocatedUnfairLock` rather than `Mutex`, which needs iOS 18; switch to `Mutex` once iOS 18
// is the minimum.

/// Where `NetworkMockingURLProtocol` finds the rules in effect: those of each ``NetworkMocking``
/// whose session is open, newest first.
package final class NetworkMockingRoute: Sendable {
    /// The route the URL protocol reads.
    package static let shared = NetworkMockingRoute()

    private let entries = OSAllocatedUnfairLock<[(owner: ObjectIdentifier, mocks: ActiveNetworkMocks)]>(initialState: [])

    /// A route with nothing in effect.
    package init() {}

    /// Puts `mocks` in effect for `owner`, in place of what it had.
    package func activate(_ mocks: ActiveNetworkMocks, for owner: ObjectIdentifier) {
        entries.withLock { entries in
            entries.removeAll { $0.owner == owner }
            entries.append((owner, mocks))
        }
    }

    /// Takes `owner`'s rules out of effect; does nothing when it has none.
    package func deactivate(_ owner: ObjectIdentifier) {
        entries.withLock { entries in
            entries.removeAll { $0.owner == owner }
        }
    }

    /// Whether a rule in effect answers a request of `method` to `url`.
    ///
    /// - Complexity: O(*n*) in the number of rules in effect.
    package func claims(method: String, url: URL) -> Bool {
        entries.withLock { entries in
            entries.reversed().contains { $0.mocks.answer(method: method, url: url) != nil }
        }
    }

    /// The answer to a request of `method` to `url`, with how it is conditioned, its failure
    /// decided now; `nil` when no rule in effect answers it.
    ///
    /// - Complexity: O(*n*) in the number of rules and profiles in effect.
    package func resolve(method: String, url: URL) -> NetworkMockingMatch? {
        let found = entries.withLock { entries in
            entries.reversed().lazy.compactMap { entry in
                entry.mocks.answer(method: method, url: url).map { (entry.mocks, $0) }
            }.first
        }
        guard let (mocks, answer) = found else { return nil }
        return NetworkMockingMatch(answer: answer, plan: mocks.plan(for: url))
    }
}

/// What answers one request: a rule's answer, and the plan of the profile that conditions it, if
/// any.
package struct NetworkMockingMatch: Sendable {
    /// The rule's answer.
    package let answer: NetworkMockAnswer
    /// How the answer is conditioned; `nil` sends it at once.
    package let plan: NetworkConditionPlan?
}

/// The rules and profiles of one open session, compiled: what the URL protocol answers from until
/// the session's expiry.
package struct ActiveNetworkMocks: Sendable {
    package struct Rule: Sendable {
        let matcher: CompiledNetworkMockMatcher
        let answer: NetworkMockAnswer
    }

    package struct Condition: Sendable {
        let host: CompiledPattern
        let profile: NetworkConditionProfile
    }

    let expires: Date
    let now: @Sendable () -> Date
    let allowedHosts: [NetworkMocking.AllowedHost]
    let rules: [Rule]
    let conditions: [Condition]
    let scheduler: any NetworkConditionScheduler
    let random: any NetworkConditionRandomSource

    /// The rules and profiles that compile, the enabled ones, in order.
    ///
    /// - Parameters:
    ///   - rules: The session's rules; one with a file body answers with an empty body.
    ///   - conditions: The session's profiles.
    ///   - allowedHosts: The hosts the app allows answers for.
    ///   - expires: When the session expires; nothing is answered from then on.
    ///   - now: The time now.
    ///   - scheduler: What times latency and bandwidth.
    ///   - random: What decides failures.
    package init(
        rules: [NetworkMockRule],
        conditions: [NetworkConditionProfile],
        allowedHosts: [NetworkMocking.AllowedHost],
        expires: Date,
        now: @escaping @Sendable () -> Date,
        scheduler: any NetworkConditionScheduler,
        random: any NetworkConditionRandomSource
    ) {
        self.rules = rules.filter(\.isEnabled).compactMap { rule in
            guard let matcher = try? CompiledNetworkMockMatcher(rule.matcher) else { return nil }
            return Rule(matcher: matcher, answer: rule.answer { _ in nil })
        }
        self.conditions = conditions.filter(\.isEnabled).compactMap { profile in
            guard let host = try? CompiledPattern(profile.host, separator: ".", caseInsensitive: true) else { return nil }
            return Condition(host: host, profile: profile)
        }
        self.allowedHosts = allowedHosts
        self.expires = expires
        self.now = now
        self.scheduler = scheduler
        self.random = random
    }

    /// The answer of the first rule matching a request of `method` to `url`, when the session
    /// hasn't expired and the app allows `url`'s host; `nil` otherwise.
    func answer(method: String, url: URL) -> NetworkMockAnswer? {
        guard url.scheme == "http" || url.scheme == "https" else { return nil }
        guard let host = url.host(), allowedHosts.contains(where: { $0.allows(host) }) else { return nil }
        guard now() < expires else { return nil }
        return rules.first { $0.matcher.matches(method: method, url: url) }?.answer
    }

    /// How the first profile matching `url`'s host conditions the answer, with its failure decided
    /// now; `nil` when none matches.
    func plan(for url: URL) -> NetworkConditionPlan? {
        let host = url.host() ?? ""
        guard let profile = conditions.first(where: { $0.host.matches(host) })?.profile else { return nil }
        return NetworkConditionPlan(effect: profile.effect(failing: random), scheduler: scheduler)
    }
}
