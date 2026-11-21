import DebugDrawerReceiver

// The capability lives with the overrides, not in the receiver: the receiver knows models, not
// plugins, and a host that offers no overrides links none of this. Its scope is the session,
// always: the overrides are for the person reviewing, and text left at the largest size or motion
// left reduced after the sidecar leaves would greet whoever holds the device next, with nothing
// saying why. Rejected: a scope parameter defaulting to the session (a host could keep an override
// past it).

public extension DebugDrawerReceiverCapability {
    /// Dynamic Type, Increase Contrast and Reduce Motion overridden for the SwiftUI views under
    /// `accessibilityEnvironmentOverrides(_:)`: a sidecar sees the overrides and, within a session,
    /// sets them; as the session ends or expires every value is the system's again.
    ///
    /// ```swift
    /// receiver.enable(.accessibilityEnvironmentOverrides())
    /// ```
    ///
    /// - Parameter overrides: The overrides the host's root view applies;
    ///   ``AccessibilityEnvironmentOverrides/shared`` unless given.
    /// - Returns: The capability, under ``AccessibilityEnvironmentOverrides/pluginID``, scoped to
    ///   the session and reverted with ``AccessibilityEnvironmentOverrides/Command/reset``.
    static func accessibilityEnvironmentOverrides(_ overrides: AccessibilityEnvironmentOverrides = .shared) -> Self {
        // The overrides live in memory and go with the process, so the receiver keeps no record.
        .model(overrides, id: AccessibilityEnvironmentOverrides.pluginID, scope: .session(revertWith: .reset))
            .recordingNoUnrevertedChanges()
    }
}
