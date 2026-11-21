import DebugDrawerReceiver

// The capability lives with the rules' vocabulary, not in the receiver: the receiver knows models,
// not plugins, and a host that offers no mocking links none of this. It is high risk (the charter's
// D9): a sidecar could make the employee's app see responses the server never sent. So it always
// requires a grant listing it, even without a grant policy (where no session has one, so it is
// refused), it answers only hosts the app allows, its scope is the session, always, and the app
// shows that it is active through the snapshot. Rejected: a scope parameter (a host could keep
// mocks past the session), and a grant left to the host's choice (team signing alone would let any
// sidecar build rewrite responses).

public extension DebugDrawerReceiverCapability {
    /// Mock responses and conditioning from a sidecar for the requests the app sends through a
    /// session listing ``NetworkMockingURLProtocol``, to the hosts `mocking` allows: a sidecar sees
    /// the allowed hosts and, within a session whose grant lists ``NetworkMocking/pluginID``, sets
    /// rules and profiles; as the session ends or expires, every request reaches the server again.
    ///
    /// It requires a grant: in a receiver whose sessions have no `DebugDrawerGrantPolicy`, every
    /// command to it is refused as `DebugDrawerAuditEntry.Refusal.grantMissing`.
    ///
    /// ```swift
    /// receiver.enable(.networkMocking(mocking))
    /// ```
    ///
    /// - Parameter mocking: The model, made with the receiver's sessions and the allowed hosts.
    /// - Returns: The capability, under ``NetworkMocking/pluginID``, requiring a grant, scoped to
    ///   the session and reverted with ``NetworkMocking/Command/reset``.
    static func networkMocking(_ mocking: NetworkMocking) -> Self {
        .model(mocking, id: NetworkMocking.pluginID, scope: .session(revertWith: .reset), refusal: NetworkMocking.refusal(for:))
            .requiringGrant()
            // The rules live in memory and go with the process, so the receiver keeps no record.
            .recordingNoUnrevertedChanges()
    }
}
