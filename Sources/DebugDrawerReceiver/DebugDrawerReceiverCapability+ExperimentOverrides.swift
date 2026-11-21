import Foundation

extension DebugDrawerReceiverCapability {
    /// Experiment (A/B test) overrides through the host's adapter to its experiment service: a
    /// sidecar sees the experiments the adapter lists, with their variants and the app's
    /// assignment, and, within a session, forces a variant so an employee can see each arm in
    /// production.
    ///
    /// The risk it takes: a forced variant is not a real assignment, so the events of a device
    /// that forces one would pollute the experiment's data. The adapter's
    /// ``DebugDrawerExperimentAdapter/overriddenExperimentsDidChange(_:)`` hears which experiments
    /// are overridden as the capability is made and at every change, and
    /// ``DebugDrawerExperimentOverrides/isExcludedFromAnalytics`` says so at any time, so the host
    /// leaves the device out of the experiments' analysis for as long as any override is in
    /// effect. It is off until the host enables it, and the host marks which experiments an
    /// employee may force by listing them, and only them, in the adapter's
    /// ``DebugDrawerExperimentAdapter/overridableExperiments()``: a command for any other
    /// experiment, or naming a variant the experiment doesn't have, is refused
    /// (``DebugDrawerAuditEntry/Refusal/notExposed``, ``DebugDrawerAuditEntry/Refusal/malformedCommand``)
    /// and changes nothing. Each override and each clear is written to the audit log as
    /// ``DebugDrawerAuditEntry/Event/commandApplied``, and the session's revert as
    /// ``DebugDrawerAuditEntry/Event/changeReverted``.
    ///
    /// With the default scope the overrides are cleared as the session ends or expires, and the
    /// adapter hears that none is left; with ``DebugDrawerChangeScope/persistent`` they stay, and
    /// the device stays excluded, across launches when the adapter keeps them, until a sidecar
    /// clears them. Session-scoped overrides a session left when the app quit during it are
    /// cleared as the capability is made, so make it as the app starts.
    ///
    /// ```swift
    /// receiver.enable(.experimentOverrides(experimentAdapter))
    /// ```
    ///
    /// - Parameters:
    ///   - adapter: The host's adapter, listing only the experiments a sidecar may see and force.
    ///   - scope: What becomes of the overrides when the session ends; by default they are
    ///     cleared.
    /// - Returns: The capability, under ``DebugDrawerExperimentOverrides/pluginID``.
    public static func experimentOverrides(
        _ adapter: some DebugDrawerExperimentAdapter,
        scope: DebugDrawerChangeScope<DebugDrawerExperimentOverrides> = .session(revertWith: .clearAllOverrides)
    ) -> Self {
        experimentOverrides(DebugDrawerExperimentOverrides(adapter: adapter), scope: scope)
    }

    /// Experiment overrides through a model the host also reads or shows elsewhere: its
    /// ``DebugDrawerExperimentOverrides/isExcludedFromAnalytics`` from an analytics pipeline, or
    /// the model in its debug build's drawer.
    ///
    /// It takes the same risk and limits as the capability made over an adapter. With a session
    /// scope, the model performs the scope's revert as the capability is made, clearing what a
    /// session left when the app quit during it, so make it as the app starts.
    ///
    /// - Parameters:
    ///   - model: The overrides' model.
    ///   - scope: What becomes of the overrides when the session ends; by default they are
    ///     cleared.
    /// - Returns: The capability, under ``DebugDrawerExperimentOverrides/pluginID``.
    public static func experimentOverrides(
        _ model: DebugDrawerExperimentOverrides,
        scope: DebugDrawerChangeScope<DebugDrawerExperimentOverrides> = .session(revertWith: .clearAllOverrides)
    ) -> Self {
        // Sessions live in memory, so none outlives the process: a session-scoped override the
        // model still records as it is made is one whose session never ended, and its revert is
        // owed (as for feature flag overrides).
        if case let .session(revert) = scope.kind, !model.snapshot.overriddenKeys.isEmpty {
            model.perform(revert)
        }
        // The model reverts what a killed launch left itself, above, so the receiver keeps no record.
        return .model(model, id: DebugDrawerExperimentOverrides.pluginID, scope: scope, refusal: model.refusal(of:))
            .recordingNoUnrevertedChanges()
    }
}
