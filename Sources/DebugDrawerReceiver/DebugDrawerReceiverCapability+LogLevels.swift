import Foundation

extension DebugDrawerReceiverCapability {
    /// Log level elevation through the host's adapter to its logger: a sidecar sees the subsystems
    /// the adapter lists, with their levels, and, within a session, raises one so an employee can
    /// read what a release build logs at a verbose level while reproducing a problem.
    ///
    /// The risk it takes: verbose levels log more of what the app handles, personal data among it.
    /// The receiver captures no log line and sends none to the sidecar: the raised lines go where
    /// the host's logger already writes them, through the redaction it applies to every line
    /// (os_log's private interpolations, a handler that masks fields), so keep that redaction on
    /// at the verbose levels. It is off until the host enables it, and the host marks which
    /// subsystems an employee may raise, and to which levels, by listing them, and only them, in
    /// the adapter's ``DebugDrawerLogLevelAdapter/elevatableSubsystems()``: a command for any other
    /// subsystem, or naming a level the subsystem doesn't list, is refused
    /// (``DebugDrawerAuditEntry/Refusal/notExposed``, ``DebugDrawerAuditEntry/Refusal/malformedCommand``)
    /// and changes nothing. Each change is written to the audit log as
    /// ``DebugDrawerAuditEntry/Event/commandApplied``, and the session's reset as
    /// ``DebugDrawerAuditEntry/Event/changeReverted``.
    ///
    /// Levels last for the session, always: as it ends or expires (its maximum duration or its
    /// grant's expiry), or a gate turns it off, the adapter is told to reset each subsystem the
    /// sidecar raised. Levels a session left when the app quit or was killed during it are reset
    /// as the capability is made, so make it as the app starts.
    ///
    /// ```swift
    /// receiver.enable(.logLevels(logLevelAdapter))
    /// ```
    ///
    /// - Parameter adapter: The host's adapter, listing only the subsystems a sidecar may raise.
    /// - Returns: The capability, under ``DebugDrawerLogLevels/pluginID``.
    public static func logLevels(_ adapter: some DebugDrawerLogLevelAdapter) -> Self {
        logLevels(DebugDrawerLogLevels(adapter: adapter))
    }

    /// Log level elevation through a model the host also shows elsewhere, such as in its debug
    /// build's drawer.
    ///
    /// It takes the same risk and limits as the capability made over an adapter. The model resets
    /// the levels a session left when the app quit during it as the capability is made, so make it
    /// as the app starts.
    ///
    /// - Parameter model: The log levels' model.
    /// - Returns: The capability, under ``DebugDrawerLogLevels/pluginID``.
    public static func logLevels(_ model: DebugDrawerLogLevels) -> Self {
        // Sessions live in memory, so none outlives the process: a level the model still records
        // as raised as it is made is one whose session never ended, and its reset is owed. Always
        // session-scoped, with no scope parameter: a verbose level left on past the session would
        // keep writing what nobody is reading, personal data among it.
        if !model.snapshot.raisedSubsystems.isEmpty {
            model.perform(.resetAll)
        }
        return .model(model, id: DebugDrawerLogLevels.pluginID, scope: .session(revertWith: .resetAll), refusal: model.refusal(of:))
    }
}
