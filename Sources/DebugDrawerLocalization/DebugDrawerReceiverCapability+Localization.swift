import DebugDrawerReceiver

// The capability lives with the modes, not in the receiver: the receiver knows models, not
// plugins, and a host that offers no review links none of this. Its scope is the session, always:
// a review mode is for the person reviewing, and one left on after the sidecar leaves would show
// keys or accented text to whoever holds the device, with nothing saying why. Rejected: a scope
// parameter defaulting to the session (a host could keep a mode past it), and persisting the mode
// across launches.

public extension DebugDrawerReceiverCapability {
    /// Show-keys and pseudo-localization of the strings the app reads through `review`: a sidecar
    /// sees the mode and, within a session, sets it; as the session ends or expires every string
    /// shows its translation again.
    ///
    /// ```swift
    /// receiver.enable(.localizationReview())
    /// ```
    ///
    /// - Parameter review: What the app's strings are read through; ``LocalizationReview/shared``
    ///   unless given.
    /// - Returns: The capability, under ``LocalizationReview/pluginID``, scoped to the session and
    ///   reverted with ``LocalizationReview/Command/setMode(_:)`` to
    ///   ``Localization/Mode/standard``.
    static func localizationReview(_ review: LocalizationReview = .shared) -> Self {
        // The mode lives in memory and goes with the process, so the receiver keeps no record.
        .model(review, id: LocalizationReview.pluginID, scope: .session(revertWith: .setMode(.standard)))
            .recordingNoUnrevertedChanges()
    }
}
