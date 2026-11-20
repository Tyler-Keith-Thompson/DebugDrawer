import Foundation

// The host's kill switch (DD-100): a gate for the whole receiver, `isAllowed`, and one per
// capability, given at `enable(_:isAllowed:)`, each a closure the host backs with its own remote
// configuration. The library integrates no vendor: it only asks.
//
// The gates come first. A command meets them before anything else is checked or decoded, a
// session's opening included, and so before the sessions verify a sidecar's signed grant (DD-99,
// at the session's opening and at each command to a capability that requires one): the kill
// switch has to hold even when every other check would pass, and a refused sidecar's grant is
// never even read. A command
// refused by one is audited as `receiverDisabled` or `capabilityDisabled`, within the open session
// if there is one, and then the gate's effect is applied.
//
// Its effect: with the receiver's gate off the open session ends (`disabledByHost`), reverting
// its session-scoped changes, and no capability's snapshot is written, its file removed from the
// store; the sessions' own snapshot stays, so the sidecar sees its session end, and it holds only
// an ID and two dates. With one capability's gate off, that capability's snapshot goes the same
// way, and its session-scoped change in the open session is reverted at once, while the session
// and every other capability carry on: a capability turned off is meant to stop affecting the app
// now, not at the end of a session that may last a while. A gate turned back on serves the
// snapshot again, and a new session can open.
//
// A closure can't say when it changes, so the receiver asks at the events it already has: each
// command, its start, the app coming to the foreground and each snapshot it is about to write;
// and the host calls `reevaluateGates()` as its configuration changes, which ends an open session
// with no command needed. Rejected: polling the gate on a timer (work while nothing happens, and
// still late); a Combine publisher or async sequence of the flag (a host's remote configuration
// rarely offers one, and a closure is what every one of them can give); a gate on
// `DebugDrawerSessions` (the sessions also gate a debug build's registry, where the drawer is the
// developer's own and no kill switch is wanted); leaving a capability's change in place until the
// session ends (it would outlive the switch that was meant to stop it); and stopping the sessions'
// snapshot too (a sidecar left reading an active session that ended would keep sending commands).

extension DebugDrawerReceiver {
    /// Lets a sidecar read `capability` and, within a session, drive it, while `isAllowed` returns
    /// `true`, in place of any capability enabled under its ID before.
    ///
    /// While `isAllowed` returns `false`, the capability's commands are refused as
    /// ``DebugDrawerAuditEntry/Refusal/capabilityDisabled``, its snapshot leaves the store, and its
    /// session-scoped change in the open session is reverted; the session and the other
    /// capabilities carry on. The receiver asks it when it asks ``isAllowed``, and only while
    /// that returns `true`.
    ///
    /// - Parameters:
    ///   - capability: What to allow.
    ///   - isAllowed: The capability's gate, backed by your own remote configuration.
    public func enable(_ capability: DebugDrawerReceiverCapability, isAllowed: @escaping @MainActor () -> Bool) {
        enable(capability, gate: isAllowed)
    }

    /// Asks the gates now, and applies them: ends the open session if ``isAllowed`` returns
    /// `false`, reverts the session-scoped change of each capability whose gate returns `false`,
    /// and stops or resumes serving each capability's snapshot. Call it as the configuration
    /// behind the gates changes; the receiver also asks at each command, as it starts and as the
    /// app comes to the foreground.
    public func reevaluateGates() {
        apply(receiverAllowed: isAllowed())
    }

    func enable(_ capability: DebugDrawerReceiverCapability, gate: (@MainActor () -> Bool)?) {
        capabilities[capability.id] = capability
        capabilityGates[capability.id] = gate
        paused.remove(capability.id)
        guard isRunning else { return }
        if servesSnapshot(of: capability.id) {
            serve(capability.id, capability.snapshots())
        } else {
            pause(capability.id)
        }
    }

    /// Whether the gates let `id`'s snapshot be written: the sessions' always.
    func servesSnapshot(of id: String) -> Bool {
        id == DebugDrawerSessions.pluginID || (isAllowed() && capabilityGates[id]?() != false)
    }

    /// Refuses and audits a command to `id` while a gate is off, then applies the gates; whether
    /// the command may go on to the other checks.
    func passesGates(_ id: String) -> Bool {
        let receiverAllowed = isAllowed()
        let refusal: DebugDrawerAuditEntry.Refusal? =
            if !receiverAllowed {
                .receiverDisabled
            } else if capabilities[id] != nil, capabilityGates[id]?() == false {
                .capabilityDisabled
            } else {
                nil
            }
        if let refusal {
            // Before the gates' effect, so the refusal is recorded in the session it was sent in.
            sessions.refuse(id, refusal)
        }
        apply(receiverAllowed: receiverAllowed)
        return refusal == nil
    }

    private func apply(receiverAllowed: Bool) {
        if !receiverAllowed {
            sessions.end(because: .disabledByHost)
        }
        for id in capabilities.keys.sorted() {
            if receiverAllowed, capabilityGates[id]?() != false {
                if paused.remove(id) != nil, isRunning, let capability = capabilities[id] {
                    serve(id, capability.snapshots())
                }
            } else {
                // With the receiver's gate off the session's end reverted everything already.
                sessions.revertChanges(of: id)
                pause(id)
            }
        }
    }

    /// Stops writing `id`'s snapshot and removes its file from the store.
    private func pause(_ id: String) {
        guard paused.insert(id).inserted else { return }
        writing.removeValue(forKey: id)?.cancel()
        try? FileManager.default.removeItem(at: layout.snapshotFile(for: id))
    }
}
