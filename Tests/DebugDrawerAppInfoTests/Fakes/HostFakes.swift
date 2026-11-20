// The host's services the app state reads through the receiver's capability models: a flag
// service, an experiment service and a backend switch, in memory, each a hand-written fake of the
// receiver's adapter protocol. The verifier stands in for a company's grant server.
import DebugDrawerReceiver
import Foundation

/// A flag service with live values and the overrides a sidecar sets.
@MainActor
final class FakeFlagService: DebugDrawerFeatureFlagAdapter {
    let live: [String: DebugDrawerFeatureFlagValue]
    var overrides: [String: DebugDrawerFeatureFlagValue] = [:]

    init(_ live: [String: DebugDrawerFeatureFlagValue]) {
        self.live = live
    }

    func overridableFlags() -> [DebugDrawerFeatureFlag] {
        live.keys.sorted().compactMap { key in (overrides[key] ?? live[key]).map { DebugDrawerFeatureFlag(key: key, value: $0) } }
    }

    func setOverride(_ value: DebugDrawerFeatureFlagValue, forKey key: String) {
        overrides[key] = value
    }

    func clearOverride(forKey key: String) {
        overrides[key] = nil
    }
}

/// An experiment service whose assignments the test sets, with the variants a sidecar forces.
@MainActor
final class FakeExperimentService: DebugDrawerExperimentAdapter {
    let variants: [String: [String]]
    let assigned: [String: String]
    var forced: [String: String] = [:]

    init(variants: [String: [String]], assigned: [String: String]) {
        self.variants = variants
        self.assigned = assigned
    }

    func overridableExperiments() -> [DebugDrawerExperiment] {
        variants.keys.sorted().map { key in
            DebugDrawerExperiment(key: key, variants: variants[key] ?? [], assignedVariant: forced[key] ?? assigned[key])
        }
    }

    func setOverride(variant: String, forExperiment key: String) {
        forced[key] = variant
    }

    func clearOverride(forExperiment key: String) {
        forced[key] = nil
    }

    func overriddenExperimentsDidChange(_ keys: [String]) {}
}

/// A backend switch that records the environment it was pointed at.
@MainActor
final class FakeBackend: DebugDrawerEnvironmentAdapter {
    private(set) var active: String?

    func activate(_ environment: DebugDrawerEnvironment) {
        active = environment.id
    }
}

/// Accepts every token as a grant for `audience` listing `capabilities`, valid for an hour either
/// side of now, under an ID of the token itself, so each token opens one session.
struct AcceptingGrantVerifier: DebugDrawerGrantVerifier {
    let audience: String
    let capabilities: [String]

    func verify(_ token: String) throws(DebugDrawerGrantVerificationError) -> DebugDrawerGrant {
        DebugDrawerGrant(
            id: token, subject: "employee@example.com", audiences: [audience], capabilities: capabilities,
            notBefore: Date().addingTimeInterval(-3600), expires: Date().addingTimeInterval(3600)
        )
    }
}
