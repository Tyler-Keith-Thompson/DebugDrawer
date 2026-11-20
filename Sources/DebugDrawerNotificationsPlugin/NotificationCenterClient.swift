#if DEBUG
    import DebugDrawerNotifications

    /// The notification center calls the plugin makes: User Notifications' current center in
    /// production (`SystemNotificationCenterClient`), a fake the test steers in tests.
    @MainActor
    protocol NotificationCenterClient {
        /// The app's notification settings now.
        func settings() async -> NotificationSettings

        /// Asks for alerts, badges and sounds, showing the system's prompt while the user hasn't
        /// decided.
        ///
        /// - Throws: `NotificationCenterFailure` when the system can't ask.
        func requestAuthorization() async throws(NotificationCenterFailure)

        /// The requests not yet delivered.
        func pendingNotifications() async -> [ListedNotification]

        /// The notifications still in Notification Center.
        func deliveredNotifications() async -> [ListedNotification]

        /// Adds a request that delivers `payload` after `delay`, under `identifier`.
        ///
        /// - Throws: `NotificationCenterFailure` when the system refuses the request.
        func add(_ payload: NotificationPayload, identifier: String, delay: SendDelay) async throws(NotificationCenterFailure)

        /// Removes the pending requests with these identifiers.
        func removePendingNotifications(withIdentifiers identifiers: [String])

        /// Removes every pending request.
        func removeAllPendingNotifications()

        /// Removes the delivered notifications with these identifiers from Notification Center.
        func removeDeliveredNotifications(withIdentifiers identifiers: [String])

        /// Removes every delivered notification from Notification Center.
        func removeAllDeliveredNotifications()
    }

    /// The notification center failed, for the reason the system gave.
    struct NotificationCenterFailure: Error, Equatable, Sendable {
        let message: String
    }
#endif
