import Foundation

// Serving within a session (DD-271). Any app of the group can read the store, and file reads in a
// shared container can't be observed or audited, so a capability's snapshot is in the store only
// while a sidecar could act on it: while a session is open, and, when the session has a grant (a
// grant policy) or the capability requires one (`requiringGrant()`), only while that grant lists
// the capability. Outside that the store holds the app's presence file and the sessions' snapshot
// (an ID, two dates and the grant's claims, never its token), and nothing of any capability.
//
// One rule, here, for every capability, rather than each model emptying its own snapshot: a new
// capability is covered without doing anything, and the rule can't drift between models. The
// mirrors that collect only for a session (analytics, MetricKit, push registration, app state)
// still ask `DebugDrawerSession.allows(_:)` themselves, as that decides what they collect, not
// only what is served, and a model may be served by something other than a receiver.
//
// Event-driven: the sessions record `sessionOpened` and `sessionEnded` after the state they name is
// set (end, expiry, the host's gate, `end()`), and the receiver hears both on the main actor as
// they are recorded. As a session opens, each capability it may read has its current snapshot
// written before the call returns, so it is in the store before the sessions' own snapshot, which
// is written on a later main-actor turn, says the session is open: a sidecar that reads once it
// sees the session needs no wait. As a session ends, every capability's snapshot leaves the store
// before the call returns, its writer cancelled first, so a change landing while the session's
// reverts run is never written after it.
//
// Rejected: an opt-in for a capability to serve before a session (it keeps a footgun: a host
// enabling one would publish its data to every app of the group again); auditing reads instead
// (a read of a file in a shared container can't be observed); and serving an empty snapshot
// outside a session (the file would still say which capabilities exist and when they change, and
// every model would need an empty value).

extension DebugDrawerReceiver {
    /// Whether the open session may read `id`'s snapshot: a session is open and, when it has a
    /// grant or the capability requires one, the grant lists `id`.
    func sessionReads(_ id: String) -> Bool {
        guard let session = sessions.snapshot.session, let capability = capabilities[id] else { return false }
        return session.allows(id, requiringGrant: capability.requiresGrant)
    }

    /// Starts writing each capability's snapshot the gates and the open session let a sidecar
    /// read, its current snapshot written at once, and stops writing, removing its file, each
    /// other one's.
    func updateServing() {
        for id in capabilities.keys.sorted() {
            guard let capability = capabilities[id] else { continue }
            let serves = isRunning && servesSnapshot(of: id)
            if serves, writing[id] == nil {
                serve(id, capability.snapshots(), writingFirst: capability.currentSnapshot())
            } else if !serves {
                stopServing(id)
            }
        }
    }

    /// Writes the snapshots `snapshots` delivers to `id`'s file, in place of any written for it
    /// before, having written `first`, when given, before it returns.
    func serve(_ id: String, _ snapshots: AsyncStream<Data>, writingFirst first: Data? = nil) {
        writing[id]?.cancel()
        let layout = layout
        let file = layout.snapshotFile(for: id)
        if let first {
            write(first, of: id, to: file, in: layout)
        }
        writing[id] = Task { [weak self] in
            var previous = first
            for await payload in snapshots {
                // Stopped since this snapshot was taken (a session ended): its file is gone, and
                // must stay gone.
                guard !Task.isCancelled else { return }
                // A gate turned off since the receiver last asked: stop now rather than write, once
                // the commands waiting are performed in their session (reevaluateGates()).
                guard let self, servesSnapshot(of: id) else {
                    self?.reevaluateGates()
                    return
                }
                guard payload != previous else { continue }
                previous = payload
                write(payload, of: id, to: file, in: layout)
            }
        }
    }

    /// Stops writing `id`'s snapshot and removes its file from the store, if it was being written.
    func stopServing(_ id: String) {
        guard let task = writing.removeValue(forKey: id) else { return }
        task.cancel()
        try? FileManager.default.removeItem(at: layout.snapshotFile(for: id))
    }

    /// Serves or withdraws the capabilities' snapshots as `entry` says a session opened or ended.
    func noteSessionChange(_ entry: DebugDrawerAuditEntry) {
        switch entry.event {
        case .sessionOpened, .sessionEnded:
            updateServing()
        case .commandApplied, .commandRefused, .changeReverted:
            break
        }
    }

    /// Removes every snapshot file but the sessions': what a launch before this one, killed or
    /// stopped while a session was open, left, and what a capability no longer enabled wrote.
    func removeCapabilitySnapshots() {
        let sessionsFile = layout.snapshotFile(for: DebugDrawerSessions.pluginID).lastPathComponent
        for file in layout.messageFiles(in: layout.snapshots) where file.lastPathComponent != sessionsFile {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
