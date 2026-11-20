import Foundation

// Always session-scoped, reverted with `stop`, which deletes the capture: there is no scope
// parameter, as a capture kept past its session would hold customers' data nobody is reading, in a
// container every app of the group can read. It doesn't require a grant on its own, as network
// mocking does: what it exposes is what the app logs and sends, redacted, which is what the
// analytics mirror and MetricKit payloads expose too, and it changes nothing the app does. A host
// that wants a grant for it calls `requiringGrant()` on the capability; under a grant policy every
// capability needs one that lists it anyway. The receiver hands the model the snapshot's file as it
// enables it, so the model can delete it whatever the receiver is doing.

public extension DebugDrawerReceiverCapability {
    /// Console lines and network requests the app hands `capture`, captured redacted and bounded
    /// once a sidecar starts the capture in its session, and deleted as the session ends.
    ///
    /// The risk it takes: what the app logs and sends belongs to the person using it. Nothing is
    /// captured until a sidecar sends ``DebugDrawerDiagnosticsCapture/Command/start`` in an open
    /// session; every line and request is redacted before it is kept, and the capture is bounded;
    /// it lives only in memory and in the capability's snapshot file in the app's own directory of
    /// the store, and both are deleted as the sidecar stops it, as the session ends or expires, as a
    /// gate turns it off, and, for a launch killed during a session, as the next launch enables
    /// it, so enable it at startup. Each command is audited as
    /// ``DebugDrawerAuditEntry/Event/commandApplied``, the deletion at the session's end as
    /// ``DebugDrawerAuditEntry/Event/changeReverted``.
    ///
    /// ```swift
    /// receiver.enable(.diagnosticsCapture(capture))
    /// ```
    ///
    /// - Parameter capture: The capture, made with the receiver's sessions.
    /// - Returns: The capability, under ``DebugDrawerDiagnosticsCapture/pluginID``, scoped to the
    ///   session and reverted with ``DebugDrawerDiagnosticsCapture/Command/stop``.
    static func diagnosticsCapture(_ capture: DebugDrawerDiagnosticsCapture) -> Self {
        var capability = Self.model(capture, id: DebugDrawerDiagnosticsCapture.pluginID, scope: .session(revertWith: .stop))
        capability.enabled = { snapshotFile in capture.attach(snapshotFile: snapshotFile) }
        return capability
    }
}
