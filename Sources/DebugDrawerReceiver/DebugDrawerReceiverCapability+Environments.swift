import Foundation

extension DebugDrawerReceiverCapability {
    /// Environment switching: a sidecar lists the host's backends and, within a session, points a
    /// production app at one the host allows (staging, a canary) for dogfooding, until the session
    /// ends.
    ///
    /// The risk is high: an employee holding the sidecar, or anyone holding a leaked one, can send
    /// the app's traffic, the user's credentials with it, to another backend. So a sidecar can only
    /// pick from the host's allowlist, which can't be empty: the capability takes a default and at
    /// least one allowed environment, each an ID, a title and a summary with no URL. The host's
    /// ``DebugDrawerEnvironmentAdapter`` maps the ID to its own configuration, which never leaves
    /// the app, and no command or snapshot has a field a URL could travel in. A command naming an
    /// environment the host didn't list is refused (``DebugDrawerAuditEntry/Refusal/notExposed``)
    /// and changes nothing. With a ``DebugDrawerGrantPolicy`` on the sessions, a switch needs a
    /// session whose grant lists ``DebugDrawerEnvironments/pluginID``; add ``requiringGrant()`` to
    /// need one even without a policy. It is off until the host enables it, each switch is written to
    /// the audit log as ``DebugDrawerAuditEntry/Event/commandApplied``, and the return to the
    /// default as ``DebugDrawerAuditEntry/Event/changeReverted``.
    ///
    /// The switch lasts for the session, always: as it ends or expires, or a gate turns it off, the
    /// adapter is told to activate the default. A switch a session left when the app quit or was
    /// killed during it is undone as the capability is made, so make it as the app starts, before
    /// the app's first request. Show the host's session indicator, naming the environment, while
    /// ``DebugDrawerEnvironments/Snapshot/isSwitched``.
    ///
    /// ```swift
    /// receiver.enable(.environments(
    ///     default: DebugDrawerEnvironment("production", title: "Production"),
    ///     allowing: DebugDrawerEnvironment("staging", title: "Staging"),
    ///     DebugDrawerEnvironment("canary", title: "Canary"),
    ///     adapter: backendSwitcher
    /// ))
    /// ```
    ///
    /// Traps when two environments, the default included, share an ID.
    ///
    /// - Parameters:
    ///   - defaultEnvironment: The environment the app starts in and returns to as each session
    ///     ends.
    ///   - first: An environment a sidecar may switch the app to.
    ///   - rest: More environments a sidecar may switch the app to, in the order to list them.
    ///   - adapter: The host's adapter, which maps each environment's ID to its own configuration.
    /// - Returns: The capability, under ``DebugDrawerEnvironments/pluginID``.
    public static func environments(
        default defaultEnvironment: DebugDrawerEnvironment,
        allowing first: DebugDrawerEnvironment,
        _ rest: DebugDrawerEnvironment...,
        adapter: some DebugDrawerEnvironmentAdapter
    ) -> Self {
        // A variadic parameter can't be forwarded to another, so the model is made from the list.
        environments(DebugDrawerEnvironments(default: defaultEnvironment, allowing: first, rest, adapter: adapter, defaults: .standard))
    }

    /// Environment switching over a model the host also shows elsewhere, such as in its debug
    /// build's drawer.
    ///
    /// It takes the same risk and limits as the capability made over environments. The model
    /// undoes a switch a session left when the app quit during it as the capability is made, so
    /// make it as the app starts.
    ///
    /// - Parameter model: The environments' model.
    /// - Returns: The capability, under ``DebugDrawerEnvironments/pluginID``.
    public static func environments(_ model: DebugDrawerEnvironments) -> Self {
        // Sessions live in memory, so none outlives the process: an environment the model still
        // records as switched as it is made is one whose session never ended, and its revert is
        // owed. Always session-scoped, with no scope parameter: a backend left switched past the
        // session would send the employee's real use there.
        if model.snapshot.isSwitched {
            model.perform(.reset)
        }
        return .model(model, id: DebugDrawerEnvironments.pluginID, scope: .session(revertWith: .reset), refusal: model.refusal(of:))
    }
}
