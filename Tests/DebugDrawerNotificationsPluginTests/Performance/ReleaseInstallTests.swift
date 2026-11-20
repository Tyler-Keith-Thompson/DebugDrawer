// The release stand-ins. `--config=release` builds and runs only the performance targets, so this
// is where a test is compiled without DEBUG, as an app's release build is; in debug the file is
// empty, and NotificationsInstallExitTests checks the opposite.
#if !DEBUG
    import DebugDrawer
    import DebugDrawerNotificationsPlugin
    import Foundation
    import Testing

    @Suite
    struct ReleaseInstallTests {
        /// What a registration failure reports.
        struct RegistrationFailed: Error {}

        @MainActor
        @Test("In release, every call compiles and does nothing: no plugin is registered")
        func installRegistersNothing() {
            // The binary links User Notifications whatever the plugin does: it re-exports
            // DebugDrawerNotifications, whose push registration capability reads the notification
            // settings in release builds, so the framework's absence can't show that the
            // calls did nothing. The drawer's registry, a release stand-in, holds no plugin.
            PushNotifications.install()
            PushNotifications.didRegisterForRemoteNotifications(withDeviceToken: Data([0xAB, 0xCD]))
            PushNotifications.didFailToRegisterForRemoteNotifications(withError: RegistrationFailed())

            #expect(DebugDrawer.shared.globalPlugins.isEmpty)
        }
    }
#endif
