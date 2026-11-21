import Foundation

// Always session-scoped, reverted with `deleteAll`: there is no scope parameter, as a report kept
// past its session would hold a screenshot and logs nobody is reading, in a container every app of
// the group can read. It doesn't require a grant on its own: what a report holds is what the
// employee had on screen and what the diagnostics capture and the host's state already expose,
// redacted, and it changes nothing the app does. A host that wants one calls `requiringGrant()`.
// The receiver hands the model the snapshot's file and its way of applying a trigger as it enables
// the capability, so a trigger meets the same gates as a sidecar's command.

public extension DebugDrawerReceiverCapability {
    /// Bug reports the host triggers during a sidecar's session, each a screenshot of the key
    /// window, the session's recent log lines and the host's state, read by the sidecar, which
    /// annotates and sends them; the app never sends one.
    ///
    /// The risk it takes: a report holds what was on the employee's screen, which isn't redacted,
    /// and what the app logs and its state, which are. A report is taken only as the host calls
    /// ``DebugDrawerBugReports/trigger(note:)`` from a trigger of its own (the library adds no
    /// gesture, key or button), only within an open session, and through the same gates as a
    /// sidecar's command: off until the host enables it, refused while a gate turns it off, and,
    /// under a grant policy or after ``requiringGrant()``, refused without a grant listing it. Each
    /// report is audited as ``DebugDrawerAuditEntry/Event/commandApplied``. Reports live in memory
    /// and in the capability's snapshot file in the app's own directory of the store, bounded
    /// (``DebugDrawerBugReports/Limits``), and are deleted as the session ends or expires (audited
    /// ``DebugDrawerAuditEntry/Event/changeReverted``), as a gate turns the capability off, as the
    /// sidecar deletes them, and, for a launch killed during a session, as the next launch enables
    /// it, so enable it at startup.
    ///
    /// ```swift
    /// receiver.enable(.bugReports(reports))
    /// ```
    ///
    /// - Parameter reports: The bug reports, made with the receiver's sessions.
    /// - Returns: The capability, under ``DebugDrawerBugReports/pluginID``, scoped to the session and
    ///   reverted with ``DebugDrawerBugReports/Command/deleteAll``.
    static func bugReports(_ reports: DebugDrawerBugReports) -> Self {
        var capability = Self.model(
            reports, id: DebugDrawerBugReports.pluginID, scope: .session(revertWith: .deleteAll), refusal: reports.refusal(of:)
        )
        capability.enabled = { snapshotFile, applyHostChange in
            reports.attach(snapshotFile: snapshotFile, applyHostChange: applyHostChange)
        }
        // What it keeps it removes as the next launch enables it (the snapshot file it is handed), so
        // the receiver keeps no record of its changes.
        return capability.recordingNoUnrevertedChanges()
    }
}
