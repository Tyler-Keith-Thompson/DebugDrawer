import DebugDrawerReceiver

// The capability lives with the build's metadata, not in the receiver: App Info reads the same
// Info.plist keys, and a host that doesn't offer it links none of this. Its one command only reads
// the state again, which changes nothing a session's end would undo, so its scope is persistent.

public extension DebugDrawerReceiverCapability {
    /// A read-only snapshot of the app's state, served to a sidecar while its session is open and
    /// attached by the sidecar to every report: the version, build, commit, branch and CI build,
    /// and only what the host registers on the model beside them.
    ///
    /// The risk it takes is low: whoever holds the sidecar learns which build and configuration
    /// the app runs (its flag and experiment overrides, experiment buckets and environment, when
    /// the host registers them) and, when the host registers a user ID, a hash of it. The ID is
    /// hashed in the process, under a key of the install's own that never leaves the app, so the
    /// sidecar can correlate one install's reports without learning the ID or testing a guess
    /// against it. Raw user IDs, tokens and keychain values are never read by the model; the
    /// host's own values are its choice, so never register a secret there. It is off until the
    /// host enables it, and every field beyond the build is off until the host registers it.
    /// Served only during a session: outside one the snapshot holds nothing, and under a grant
    /// policy a session whose grant doesn't list ``DebugDrawerAppState/pluginID`` is served
    /// nothing. The one command, ``DebugDrawerAppState/Command/refresh``, only reads the state
    /// again, and like every command is refused outside a session.
    ///
    /// ```swift
    /// let appState = try DebugDrawerAppState(sessions: sessions, environments: environments, userID: { account.userID })
    /// receiver.enable(.appState(appState))
    /// ```
    ///
    /// - Parameter appState: The model, made with the receiver's sessions and the sources the host
    ///   registers.
    /// - Returns: The capability, under ``DebugDrawerAppState/pluginID``.
    static func appState(_ appState: DebugDrawerAppState) -> Self {
        .model(appState, id: DebugDrawerAppState.pluginID, scope: .persistent)
    }
}
