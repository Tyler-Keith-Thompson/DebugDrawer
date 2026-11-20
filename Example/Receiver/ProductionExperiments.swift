import Combine
import DebugDrawerReceiver

/// The example's experiment service: assignments in memory, with forced variants winning, which a
/// sidecar sets through the experiment overrides capability. It hears which experiments are forced
/// and, standing in for the app's analytics, keeps them as the exclusion its events would carry.
@MainActor
final class ProductionExperiments: ObservableObject, DebugDrawerExperimentAdapter {
    private let variants: [String: [String]] = [
        "checkout-flow": ["control", "one-page", "express"],
        "onboarding": ["control", "video"]
    ]
    private let assignments: [String: String] = ["checkout-flow": "control", "onboarding": "control"]
    @Published private var forced: [String: String] = [:]
    /// The experiments the analytics leave this device out of: those a sidecar forced.
    @Published private(set) var analyticsExclusions: [String] = []

    func variant(forExperiment key: String) -> String? {
        forced[key] ?? assignments[key]
    }

    func overridableExperiments() -> [DebugDrawerExperiment] {
        variants.keys.sorted().compactMap { key in
            variants[key].map { DebugDrawerExperiment(key: key, variants: $0, assignedVariant: variant(forExperiment: key)) }
        }
    }

    func setOverride(variant: String, forExperiment key: String) {
        forced[key] = variant
    }

    func clearOverride(forExperiment key: String) {
        forced[key] = nil
    }

    func overriddenExperimentsDidChange(_ keys: [String]) {
        analyticsExclusions = keys
    }
}
