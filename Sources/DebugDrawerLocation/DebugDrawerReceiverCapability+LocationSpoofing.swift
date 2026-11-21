import DebugDrawerReceiver

// The capability lives with the coordinate, not in the receiver: the receiver knows models, not
// plugins, and a host that offers no spoofing links none of this. Its scope is the session, always:
// a location left spoofed past the session would put the employee's real use somewhere they aren't.

public extension DebugDrawerReceiverCapability {
    /// Location spoofing: within a session, a sidecar replaces the locations the app reads through
    /// `spoofing` with a coordinate of its own, to test geo features (a store finder, a delivery
    /// zone) on the build that ships, until the session ends.
    ///
    /// The risk is high: whoever holds the sidecar, a leaked copy included, can make the app believe
    /// the device is anywhere, which is what location-based fraud does. So nothing is intercepted:
    /// only the readings the app passes through ``LocationSpoofing/location(replacing:)`` or
    /// ``LocationSpoofing/locations(replacing:)`` are spoofed, and the app is told as spoofing starts,
    /// moves and ends (`spoofingDidChange`, ``LocationSpoofing/isSpoofing``), so its own fraud checks
    /// can react. A coordinate off the Earth is refused
    /// (``/DebugDrawerReceiver/DebugDrawerAuditEntry/Refusal/malformedCommand``). With a
    /// ``/DebugDrawerReceiver/DebugDrawerGrantPolicy`` on the sessions, a spoof needs a session whose
    /// grant lists ``LocationSpoofing/pluginID``; add
    /// ``/DebugDrawerReceiver/DebugDrawerReceiverCapability/requiringGrant()`` to need one even
    /// without a policy. It is off until the host enables it, each spoof is written to the audit
    /// log as ``/DebugDrawerReceiver/DebugDrawerAuditEntry/Event/commandApplied``, and the return to
    /// real readings as ``/DebugDrawerReceiver/DebugDrawerAuditEntry/Event/changeReverted``.
    ///
    /// The spoof lasts for the session, always: as it ends or expires, or a gate turns it off, the
    /// readings are real again and the host is told. A spoof a launch was killed in ends with the
    /// process; the host is told so as the next launch makes the capability, so make it as the app
    /// starts. Show the host's session indicator, saying the location is spoofed, while
    /// ``LocationSpoofing/Snapshot/isSpoofing``.
    ///
    /// ```swift
    /// receiver.enable(.locationSpoofing(spoofing))
    /// ```
    ///
    /// - Parameter spoofing: What the app reads its locations through.
    /// - Returns: The capability, under ``LocationSpoofing/pluginID``, scoped to the session and
    ///   reverted with ``LocationSpoofing/Command/stop``.
    static func locationSpoofing(_ spoofing: LocationSpoofing) -> Self {
        // Sessions live in memory, so none outlives the process: a flag the model finds as the
        // capability is made is a spoof whose session never ended, and the host is owed its end.
        if spoofing.isLeftByKilledLaunch {
            spoofing.endSpoofLeftByKilledLaunch()
        }
        // The model ends what a killed launch left itself, above, so the receiver keeps no record.
        return .model(spoofing, id: LocationSpoofing.pluginID, scope: .session(revertWith: .stop), refusal: spoofing.refusal(of:))
            .recordingNoUnrevertedChanges()
    }
}
