import Foundation

extension DebugDrawerReceiverCapability {
    /// Allowlisted UserDefaults: a sidecar reads the keys the host lists, and only those, and within
    /// a session edits them, each within its declared kind.
    ///
    /// The risk is medium: whoever holds the sidecar can change any allowlisted value, and with it
    /// whatever the app derives from that value. They can't read or write any other key: the
    /// domain is never listed, a command naming a key the host didn't list is refused
    /// (``DebugDrawerAuditEntry/Refusal/notExposed``), and a value its kind doesn't take, of
    /// another kind or out of bounds, is refused (``DebugDrawerAuditEntry/Refusal/malformedCommand``);
    /// neither changes anything. It is off until the host enables it, and enabled with no key it
    /// lists nothing. Never allowlist a key holding a secret (a token, a password): its value is
    /// shown to the sidecar and written to the audit log.
    ///
    /// Each edit is written to the audit log as ``DebugDrawerAuditEntry/Event/commandApplied``
    /// with the key and its value before and after in ``DebugDrawerAuditEntry/changes``, and the
    /// session's revert as ``DebugDrawerAuditEntry/Event/changeReverted`` with what it put back.
    ///
    /// With the default scope the edits last for the session: as it ends or expires, or a gate
    /// turns the receiver or the capability off, each edited key is put back as it was before its
    /// first edit, removed if it held nothing of the app's own. Edits a session left when the app
    /// quit or was killed during it are put back as the capability is made, so make it as the app
    /// starts, before it reads the keys. With ``DebugDrawerChangeScope/persistent`` they stay until a
    /// sidecar sends ``DebugDrawerUserDefaults/Command/revertAll``.
    ///
    /// ```swift
    /// try receiver.enable(.userDefaults(
    ///     .choice("plan", title: "Plan", options: ["free", "pro"]),
    ///     .bool("showsTips", title: "Shows Tips")
    /// ))
    /// ```
    ///
    /// - Parameters:
    ///   - keys: The keys a sidecar may read and edit, in the order to list them.
    ///   - defaults: The defaults the keys are in.
    ///   - scope: What becomes of the edits when the session ends; by default they are reverted.
    /// - Returns: The capability, under ``DebugDrawerUserDefaults/pluginID``.
    /// - Throws: ``DebugDrawerUserDefaults/InvalidKeys`` when a key is empty or one of
    ///   DebugDrawer's own, a key's kind contradicts itself, or a key is listed twice.
    public static func userDefaults(
        _ keys: DebugDrawerUserDefaultsKey...,
        defaults: UserDefaults = .standard,
        scope: DebugDrawerChangeScope<DebugDrawerUserDefaults> = .session(revertWith: .revertAll)
    ) throws(DebugDrawerUserDefaults.InvalidKeys) -> Self {
        // A variadic parameter can't be forwarded to another, so the model is made from the list.
        try userDefaults(DebugDrawerUserDefaults(keys: keys, defaults: defaults), scope: scope)
    }

    /// Allowlisted UserDefaults over a model the host also shows elsewhere, such as in its debug
    /// build's drawer.
    ///
    /// It takes the same risk and limits as the capability made over keys. With a session scope,
    /// the model puts back the edits a session left when the app quit during it as the capability
    /// is made, so make it as the app starts.
    ///
    /// - Parameters:
    ///   - model: The allowlisted keys' model.
    ///   - scope: What becomes of the edits when the session ends; by default they are reverted.
    /// - Returns: The capability, under ``DebugDrawerUserDefaults/pluginID``.
    public static func userDefaults(
        _ model: DebugDrawerUserDefaults,
        scope: DebugDrawerChangeScope<DebugDrawerUserDefaults> = .session(revertWith: .revertAll)
    ) -> Self {
        let capabilityScope: DebugDrawerSessions.CapabilityScope
        switch scope.kind {
        case let .session(revert):
            // Sessions live in memory, so none outlives the process: an edit the model still
            // records as it is made is one whose session never ended, and its revert is owed.
            if model.hasEdits {
                model.perform(revert)
            }
            capabilityScope = .sessionRecordingChanges { model.apply(revert) }
        case .persistent:
            capabilityScope = .persistent
        }
        // The model reverts what a killed launch left itself, above, so the receiver keeps no record.
        return Self(
            id: DebugDrawerUserDefaults.pluginID,
            scope: capabilityScope,
            perform: { payload in
                guard let command = try? JSONDecoder().decode(DebugDrawerUserDefaults.Command.self, from: payload) else {
                    return .refused(.malformedCommand)
                }
                if let reason = model.refusal(of: command) {
                    return .refused(reason)
                }
                return .applied(changes: model.apply(command))
            },
            snapshots: { encodedSnapshots(of: model) },
            currentSnapshot: { try? TransportMessage.payload(model.snapshot) }
        )
        .recordingNoUnrevertedChanges()
    }
}
