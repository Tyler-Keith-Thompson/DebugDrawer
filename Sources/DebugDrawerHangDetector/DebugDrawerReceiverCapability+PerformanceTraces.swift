import DebugDrawerReceiver
import Foundation

// Always session-scoped, reverted with `stop`, which ends the monitor and deletes the recording:
// there is no scope parameter, as a recording kept past its session would leave a run loop
// observer and a watcher thread running in the app with no sidecar to read them. It doesn't require
// a grant on its own: what it exposes is the app's own code (stacks of addresses and the exported
// symbols the system's libraries carry) and timings, no user data, and it changes nothing the app
// does. A host that wants a grant for it calls `requiringGrant()`; under a grant policy every
// capability needs one that lists it anyway. The receiver hands the model the snapshot's file as it
// enables it, so the model can delete it whatever the receiver is doing.

public extension DebugDrawerReceiverCapability {
    /// The main thread's hitches and hangs with their stacks, and the signpost intervals the host
    /// marks on `traces`, recorded once a sidecar starts the recording in its session, and deleted
    /// as the session ends.
    ///
    /// The risk it takes is low: someone holding the sidecar sees stack traces and timings of the
    /// app's own code. No user data is recorded (an interval's name is a string literal in the
    /// app's code), and nothing a sidecar sends is executed. Nothing runs until a sidecar sends
    /// ``PerformanceTraces/Command/start`` in an open session: no run loop observer, no watcher
    /// thread, no interval kept. The recording is bounded; it lives only in memory and in the
    /// capability's snapshot file in the app's own directory of the store, and both are deleted,
    /// the observer removed and the thread ended, as the sidecar stops it, as the session ends or
    /// expires, as a gate turns it off, and, for a launch killed during a session, as the next
    /// launch enables it, so enable it at startup. Each command is audited as
    /// ``DebugDrawerAuditEntry/Event/commandApplied``, the stop at the session's end as
    /// ``DebugDrawerAuditEntry/Event/changeReverted``. ``PerformanceTraces`` documents what
    /// recording costs.
    ///
    /// ```swift
    /// receiver.enable(.performanceTraces(traces))
    /// ```
    ///
    /// - Parameter traces: The recorder, made with the receiver's sessions.
    /// - Returns: The capability, under ``PerformanceTraces/pluginID``, scoped to the session and
    ///   reverted with ``PerformanceTraces/Command/stop``.
    static func performanceTraces(_ traces: PerformanceTraces) -> Self {
        var capability = Self.model(traces, id: PerformanceTraces.pluginID, scope: .session(revertWith: .stop))
        capability.enabled = { snapshotFile, _ in traces.attach(snapshotFile: snapshotFile) }
        return capability
    }
}
