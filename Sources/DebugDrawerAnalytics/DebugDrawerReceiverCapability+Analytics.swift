import DebugDrawerReceiver

// The capability lives with the analytics sink, not in the receiver: the receiver knows models,
// not plugins, and a host that mirrors no events links none of this. Its one command, clear, only
// drops what the sidecar already read, and the session's events go with the session anyway, so its
// scope is persistent: there is nothing to revert.

public extension DebugDrawerReceiverCapability {
    /// The analytics events `AnalyticsEvents.record` records while a sidecar's session is open,
    /// redacted in the app by `redaction` before they are kept or written anywhere: a sidecar sees
    /// them in ``AnalyticsEventsMirror/Snapshot`` as they arrive. Nothing recorded before the
    /// session opens, or after it ends or expires, reaches it.
    ///
    /// ```swift
    /// receiver.enable(.analyticsEvents(sessions: sessions, redaction: .standard.adding(keys: ["customer_name"])))
    /// ```
    ///
    /// - Parameters:
    ///   - sessions: The receiver's sessions, which the mirror follows.
    ///   - redaction: The rules every event is redacted by; ``AnalyticsRedaction/standard`` unless
    ///     given.
    ///   - capacity: The most events of a session a snapshot keeps, the newest.
    /// - Returns: The capability, under ``AnalyticsEventsMirror/pluginID``.
    /// - Precondition: `capacity` is at least 1.
    static func analyticsEvents(
        sessions: DebugDrawerSessions,
        redaction: AnalyticsRedaction = .standard,
        capacity: Int = AnalyticsEventsMirror.defaultCapacity
    ) -> Self {
        let mirror = AnalyticsEventsMirror(sessions: sessions, redaction: redaction, capacity: capacity)
        return .model(mirror, id: AnalyticsEventsMirror.pluginID, scope: .persistent)
    }
}
