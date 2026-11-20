import Foundation

// One thing a sidecar may do in a production app, as the host enables it: a plugin model under an
// ID, with the scope that says what becomes of its changes when the session ends. A capability is
// a model because a model is already a closed vocabulary: its commands decode into the model's own
// `Command` type and nothing else, so the receiver never runs or evaluates what arrives, and its
// snapshot is all a sidecar reads, so it shows only what the model chose to put there. The model's
// type is erased here, so one receiver holds capabilities of every type. Rejected: capabilities as
// an enum the receiver switches over (every new one would change this module, and a host couldn't
// add its own), and a closure taking the raw command (it could do anything with input it was never
// meant to interpret).

/// A capability a ``DebugDrawerReceiver`` serves once the host enables it.
///
/// ```swift
/// receiver.enable(.featureFlagOverrides(flagAdapter))
/// receiver.enable(.model(logLevels, id: "MyApp.LogLevels", scope: .session(revertWith: .reset)))
/// ```
@MainActor
public struct DebugDrawerReceiverCapability {
    /// The ID a sidecar connects to it by, and the audit log names it by.
    public let id: String
    /// What becomes of its changes as the session ends.
    let scope: DebugDrawerSessions.CapabilityScope
    /// Performs the command `payload` encodes, or returns why it was refused: when it isn't one of
    /// the model's commands, or the capability refuses it.
    let perform: @MainActor (_ payload: Data) -> DebugDrawerAuditEntry.Refusal?
    /// The model's snapshots as JSON.
    let snapshots: @MainActor () -> AsyncStream<Data>

    /// A capability that drives `model`: a sidecar reads its snapshots and, within a session,
    /// sends it the model's own commands.
    ///
    /// - Parameters:
    ///   - model: The model a sidecar may read and drive.
    ///   - id: The ID a sidecar connects to it by, and the audit log names it by.
    ///   - scope: What becomes of its changes when the session ends: reverted with a command, or
    ///     kept.
    /// - Returns: The capability, for ``DebugDrawerReceiver/enable(_:)``.
    public static func model<Model: DebugDrawerPluginModel>(_ model: Model, id: String, scope: DebugDrawerChangeScope<Model>) -> Self {
        .model(model, id: id, scope: scope) { _ in nil }
    }

    /// A capability that drives `model`, refusing each decoded command `refusal` gives a reason
    /// for, before the model performs it: for a capability that knows which of its commands a
    /// sidecar may send, such as the tweaks capability, which takes only production-safe tweaks.
    ///
    /// - Parameters:
    ///   - model: The model a sidecar may read and drive.
    ///   - id: The ID a sidecar connects to it by, and the audit log names it by.
    ///   - scope: What becomes of its changes when the session ends.
    ///   - refusal: Why a command is refused, or `nil` to perform it.
    /// - Returns: The capability, for ``DebugDrawerReceiver/enable(_:)``.
    package static func model<Model: DebugDrawerPluginModel>(
        _ model: Model,
        id: String,
        scope: DebugDrawerChangeScope<Model>,
        refusal: @escaping @MainActor (Model.Command) -> DebugDrawerAuditEntry.Refusal?
    ) -> Self {
        Self(
            id: id,
            scope: DebugDrawerSessions.CapabilityScope(scope, of: model),
            perform: { payload in
                guard let command = try? JSONDecoder().decode(Model.Command.self, from: payload) else { return .malformedCommand }
                if let reason = refusal(command) {
                    return reason
                }
                model.perform(command)
                return nil
            },
            snapshots: { encodedSnapshots(of: model) }
        )
    }

    /// Feature flag overrides through the host's adapter to its flag service: a sidecar sees the
    /// flags the adapter lists and, within a session, overrides them.
    ///
    /// - Parameters:
    ///   - adapter: The host's adapter, listing only the flags a sidecar may see and override.
    ///   - scope: What becomes of the overrides when the session ends; by default they are
    ///     cleared.
    /// - Returns: The capability, under ``DebugDrawerFeatureFlagOverrides/pluginID``.
    public static func featureFlagOverrides(
        _ adapter: some DebugDrawerFeatureFlagAdapter,
        scope: DebugDrawerChangeScope<DebugDrawerFeatureFlagOverrides> = .session(revertWith: .clearAllOverrides)
    ) -> Self {
        featureFlagOverrides(DebugDrawerFeatureFlagOverrides(adapter: adapter), scope: scope)
    }

    /// Feature flag overrides through a model the host also shows elsewhere, such as in its debug
    /// build's drawer, so the same overrides can be tested in the process.
    ///
    /// - Parameters:
    ///   - model: The overrides' model.
    ///   - scope: What becomes of the overrides when the session ends; by default they are
    ///     cleared.
    /// - Returns: The capability, under ``DebugDrawerFeatureFlagOverrides/pluginID``.
    public static func featureFlagOverrides(
        _ model: DebugDrawerFeatureFlagOverrides,
        scope: DebugDrawerChangeScope<DebugDrawerFeatureFlagOverrides> = .session(revertWith: .clearAllOverrides)
    ) -> Self {
        .model(model, id: DebugDrawerFeatureFlagOverrides.pluginID, scope: scope)
    }
}
