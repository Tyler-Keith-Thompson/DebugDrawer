import Foundation
import os

// Reverting what a killed launch left (DD-267). Sessions live in memory, so a session the app quit
// or was killed in never ends, and a session-scoped change that persists outside the process (a
// tweak's stored value) would stay. The receiver keeps a record of each capability a session
// changed (UnrevertedChanges.swift) and, as the next launch enables that capability, performs its
// scope's revert and audits it as `changeReverted` in the session that made the change.
//
// Ordering, so a kill at any point leaves at worst one revert too many and never a change without
// its revert: the entry is written before the command reaches the model (inside the sessions'
// `apply`, once every check has passed, so a refused session or grant writes nothing); a command
// the capability refuses takes a new entry off again, as it changed nothing; and an entry leaves
// the record only after its revert ran, as the sessions' `changeReverted` audit entry (session
// end, expiry, a gate) or `sessionEnded` comes in, both recorded after the revert.
//
// An entry whose capability isn't enabled at the next launch stays, and is reverted in whichever
// launch enables the capability first, before or after `start()`. Rejected: dropping it at
// `start()` with an audit entry (a capability the host enables later in the launch, behind a
// remote flag or in a later version, would keep the change for good, and the audit log would
// record a revert that never ran). An entry for a capability now enabled `.persistent`, or one
// that keeps no record, is dropped with a log notice: there is no revert to run.
//
// Capabilities whose model keeps its own record beside the change and reverts it as it is made
// (feature flags, experiments, log levels, environments, location, UserDefaults), and those whose
// changes go with the process or are cleaned up as they are enabled (accessibility, localization,
// network mocking, diagnostics, bug reports, performance traces), keep none here
// (`recordingNoUnrevertedChanges()`), so nothing is reverted or audited twice. Rejected: moving
// those onto this record (their own record sits in the app's own defaults, out of the store's
// writers' reach, and their revert runs as the model is made, before the app first reads it,
// where the receiver's can run only once it is enabled).

extension DebugDrawerReceiver {
    private static let unrevertedLogger = Logger(subsystem: "DebugDrawerReceiver", category: "UnrevertedChanges")

    /// The record of the session-scoped changes owed a revert, in ``appDirectory``, read as it is
    /// first used.
    var unrevertedChanges: UnrevertedChanges {
        let file = appDirectory.appending(path: UnrevertedChanges.fileName, directoryHint: .notDirectory)
        if let unrevertedRecord, unrevertedRecord.file == file {
            return unrevertedRecord
        }
        let record = UnrevertedChanges(file: file)
        unrevertedRecord = record
        return record
    }

    /// Performs `perform`, `capability`'s change in the open session, having first recorded that
    /// the capability is owed a revert, if its scope reverts and its changes are recorded; takes
    /// the entry off again when the capability refuses the command and had changed nothing before
    /// in this session.
    func recordingChange(
        to capability: DebugDrawerReceiverCapability,
        _ perform: () -> DebugDrawerSessions.CommandOutcome
    ) -> DebugDrawerSessions.CommandOutcome {
        guard capability.recordsUnrevertedChanges, capability.scope.revert != nil, let session = sessions.snapshot.session else {
            return perform()
        }
        let record = unrevertedChanges
        let isFirstChange = !record.contains(capability.id, in: session.id)
        if isFirstChange {
            record.insert(capability.id, in: session.id)
        }
        let outcome = perform()
        if isFirstChange, case .refused = outcome {
            record.remove(capability.id, in: session.id)
        }
        return outcome
    }

    /// Reverts the change a session in a launch before this one made to `capability` and never
    /// reverted, as the app was killed or quit during it, and audits it in that session.
    func revertChangesLeftByKill(of capability: DebugDrawerReceiverCapability) {
        let record = unrevertedChanges
        guard let sessionID = record.takeLeft(capability.id) else { return }
        guard capability.recordsUnrevertedChanges, let revert = capability.scope.revert else {
            Self.unrevertedLogger.notice("Dropped \(capability.id, privacy: .public)'s unreverted change: it is enabled without a revert now")
            record.remove(capability.id, in: sessionID)
            return
        }
        Self.unrevertedLogger.notice("Reverting the change a killed launch left to \(capability.id, privacy: .public)")
        // Audited as changeReverted, which takes the entry off the record (noteReverted(_:)).
        sessions.revertChanges(of: capability.id, leftBy: sessionID, revert)
    }

    /// Takes off the record what `entry` says the sessions reverted: one capability's change, or,
    /// as a session ends, every change made in it.
    func noteReverted(_ entry: DebugDrawerAuditEntry) {
        guard let unrevertedRecord, let sessionID = entry.sessionID else { return }
        switch entry.event {
        case .changeReverted:
            unrevertedRecord.remove(entry.capability, in: sessionID)
        case .sessionEnded:
            unrevertedRecord.removeAll(in: sessionID)
        case .sessionOpened, .commandApplied, .commandRefused:
            break
        }
    }
}
