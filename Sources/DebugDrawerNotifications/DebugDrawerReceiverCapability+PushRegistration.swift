import DebugDrawerReceiver

// The capability lives with the notification settings' vocabulary, not in the receiver: the
// receiver knows models, not plugins, and a host that doesn't offer it links none of User
// Notifications' mapping. Its one command only reads the settings again, which changes nothing a
// session's end would undo, so its scope is persistent.

public extension DebugDrawerReceiverCapability {
    /// The app's APNs device token, push environment and notification authorization and settings,
    /// served to a sidecar while its session is open, so an employee can aim a test push at their
    /// own device.
    ///
    /// The risk it takes: a sidecar holding the session reads the device's token, which names it
    /// to APNs. Sending a push to it also needs the company's APNs key or certificate, which
    /// neither the app nor the sidecar holds, so the token is not a credential, and the charter's
    /// rule against exposing secrets over IPC (keychain values, tokens) doesn't bar it; it is
    /// still a device identifier, so it is treated as low-to-medium risk. It is off until the host
    /// enables it, and served only during a session: outside one the snapshot holds nothing, and
    /// under a grant policy a session whose grant doesn't list ``PushRegistrationMirror/pluginID``
    /// is served nothing. The token stays in memory and, during a session, in the capability's
    /// snapshot file in the app's own directory of the store, which is rewritten without it as the
    /// session ends or expires, removed as a gate turns the capability off, and rewritten or removed
    /// as the receiver next starts after a launch killed during a session. It is never written to
    /// the defaults, another file or a log. The one command, ``PushRegistrationMirror/Command/refresh``,
    /// only reads the settings again, and like every command is refused outside a session.
    ///
    /// ```swift
    /// let pushRegistration = PushRegistrationMirror(sessions: sessions)
    /// receiver.enable(.pushRegistration(pushRegistration))
    /// ```
    ///
    /// - Parameter mirror: The mirror, made with the receiver's sessions, that the host hands the
    ///   device token.
    /// - Returns: The capability, under ``PushRegistrationMirror/pluginID``.
    static func pushRegistration(_ mirror: PushRegistrationMirror) -> Self {
        .model(mirror, id: PushRegistrationMirror.pluginID, scope: .persistent)
    }
}
