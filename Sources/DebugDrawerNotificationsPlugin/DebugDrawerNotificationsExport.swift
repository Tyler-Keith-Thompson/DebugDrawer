// The Notifications module holds what a release build needs: the notification settings'
// vocabulary and the receiver capability that shows a sidecar the APNs device token, the push
// environment and the settings during its session, real in every build and with no drawer. The
// plugin, the drawer's half, depends on it and re-exports it, so `import
// DebugDrawerNotificationsPlugin` keeps seeing `NotificationSettings`, and both read the settings
// through the same mapping. Rejected: the capability in the receiver (the receiver would hold a
// plugin's vocabulary, and every production app would link User Notifications' mapping), and the
// plugin linked into release builds (it depends on the drawer, which a production app doesn't
// link).
@_exported import DebugDrawerNotifications
