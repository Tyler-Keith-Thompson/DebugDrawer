// What becomes of a capability's changes when the session that made them ends, declared by the
// host as it registers the capability's model, in the model's own vocabulary: the command that
// puts it back. A capability registered without one is refused under sessions, so nothing a
// sidecar changes outlives its session unless the host said it may. Rejected: a revert closure
// (it could do anything, where a command is what the model already does and a test already
// covers); restoring the snapshot taken as the session opened (a model takes commands, not
// snapshots); session scope as the default (a model with no reverting command would silently keep
// its changes). Real in every build: a value that does nothing by itself.

/// What becomes of the changes a capability's commands make when the sidecar's session ends:
/// reverted, or kept.
///
/// Pass it to ``DebugDrawerReceiverCapability/model(_:id:scope:)``, or, in a debug build, to
/// `DebugDrawerModelRegistry`'s `register(_:id:scope:)`:
///
/// ```swift
/// receiver.enable(.model(logLevels, id: "MyApp.LogLevels", scope: .session(revertWith: .resetLevels)))
/// registry.register(flagOverrides, id: "MyApp.FlagOverrides", scope: .persistent)
/// ```
public struct DebugDrawerChangeScope<Model: DebugDrawerPluginModel>: Sendable {
    enum Kind: Sendable {
        case session(revert: Model.Command)
        case persistent
    }

    let kind: Kind

    /// The capability's changes last for the session: when it ends or expires, the model performs
    /// `command`, once, if a command was applied to it in that session. Enabled on a
    /// ``DebugDrawerReceiver``, the model also performs it as the next launch enables the
    /// capability when the app was killed or quit during that session.
    ///
    /// - Parameter command: The command that puts the model back as it was before the session,
    ///   such as resetting an elevated log level.
    /// - Returns: The scope.
    public static func session(revertWith command: Model.Command) -> Self {
        Self(kind: .session(revert: command))
    }

    /// The capability's changes outlive the session, such as a feature flag's override the
    /// tester means to keep.
    public static var persistent: Self {
        Self(kind: .persistent)
    }
}
