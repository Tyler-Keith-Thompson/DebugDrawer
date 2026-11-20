import Foundation

/// The host's adapter between the receiver's experiment overrides and its experiment service
/// (Optimizely, Statsig, LaunchDarkly experiments, Firebase A/B Testing or its own).
///
/// It decides what a sidecar may touch: listing an experiment in ``overridableExperiments()``
/// marks it as one an employee may force into any of its listed variants on their own device. The
/// receiver calls it on the main actor, only with an experiment the adapter listed and one of that
/// experiment's variants, and clears only overrides it set.
///
/// A forced variant is not a real assignment, so events from a device that forces one would
/// pollute the experiment's data. ``overriddenExperimentsDidChange(_:)`` is how the host hears it:
/// the model calls it as it is made, with the overrides kept from the last launch, and again each
/// time the set of overridden experiments changes. While it holds any key, exclude this device's
/// session (or user) from the analytics of those experiments, or of every experiment.
///
/// ```swift
/// @MainActor
/// final class ExperimentAdapter: DebugDrawerExperimentAdapter {
///     func overridableExperiments() -> [DebugDrawerExperiment] {
///         [DebugDrawerExperiment(key: "checkout-flow", variants: ["control", "one-page"],
///                                assignedVariant: Experiments.shared.variant(for: "checkout-flow"))]
///     }
///
///     func setOverride(variant: String, forExperiment key: String) {
///         Experiments.shared.forceVariant(variant, for: key)
///     }
///
///     func clearOverride(forExperiment key: String) {
///         Experiments.shared.removeForcedVariant(for: key)
///     }
///
///     func overriddenExperimentsDidChange(_ keys: [String]) {
///         Analytics.shared.setUserProperty("qa_forced_experiments", keys.joined(separator: ","))
///         Analytics.shared.excludeFromExperimentAnalysis = !keys.isEmpty
///     }
/// }
/// ```
@MainActor
public protocol DebugDrawerExperimentAdapter {
    /// The experiments a sidecar may see and override, each with its variants and the variant the
    /// app is assigned now, in the order to list them.
    func overridableExperiments() -> [DebugDrawerExperiment]

    /// Makes the app read `variant` for the experiment `key` until the override is cleared.
    ///
    /// - Parameters:
    ///   - variant: One of the variants ``overridableExperiments()`` listed for the experiment.
    ///   - key: An experiment ``overridableExperiments()`` listed.
    func setOverride(variant: String, forExperiment key: String)

    /// Makes the app read the experiment service's assignment for `key` again.
    ///
    /// - Parameter key: An experiment the receiver overrode.
    func clearOverride(forExperiment key: String)

    /// The analytics exclusion hook: the experiments this device now forces a variant of, sorted,
    /// or none.
    ///
    /// Called as the model is made, with the overrides it kept from the last launch (often none),
    /// and after every change to the set. While `keys` isn't empty, mark the session or user so
    /// the experiment's analysis leaves it out.
    ///
    /// - Parameter keys: The overridden experiments' keys, sorted; empty when none is overridden.
    func overriddenExperimentsDidChange(_ keys: [String])
}
