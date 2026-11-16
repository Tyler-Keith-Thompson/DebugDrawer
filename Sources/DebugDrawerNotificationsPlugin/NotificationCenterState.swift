#if DEBUG
    /// What the plugin last read from the notification center.
    enum NotificationCenterState: Equatable, Sendable {
        /// Not read yet.
        case loading
        /// The settings, pending requests and delivered notifications as last read, less any the
        /// drawer has removed since.
        case loaded(NotificationCenterSnapshot)
    }

    /// The notification center at one read.
    struct NotificationCenterSnapshot: Equatable, Sendable {
        var settings: NotificationSettings
        var pending: [ListedNotification]
        var delivered: [ListedNotification]
    }
#endif
