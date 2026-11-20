import Foundation

/// Push and local notifications in the debug drawer: the APNs device token, the app's
/// notification authorization and settings, its pending and delivered notifications, and a
/// pasted APNs payload sent as a local notification to exercise the app's handlers.
///
/// The type exists in every build, so the calls compile unchanged in release, where they do
/// nothing and touch nothing of User Notifications.
public enum PushNotifications {
    /// Adds the Notifications plugin: in debug builds only; in release it does nothing.
    ///
    /// The plugin reads the notification settings, the pending requests and the delivered
    /// notifications when installed, each time the app becomes active, after each of its own
    /// actions and on Refresh; nothing polls. It doesn't touch the notification center's
    /// delegate, which stays the app's.
    ///
    /// Call it once at startup. Calling it again replaces the plugin with a new one, keeping the
    /// device token already reported.
    @MainActor
    public static func install() {
        #if DEBUG
            PushNotificationsInstallation.install()
        #endif
    }

    /// Shows the device token APNs gave the app: call it from the app delegate's
    /// `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`. In release it does
    /// nothing.
    ///
    /// The token is kept even when it arrives before ``install()``.
    ///
    /// - Parameter deviceToken: The token, as the delegate method receives it.
    @MainActor
    public static func didRegisterForRemoteNotifications(withDeviceToken deviceToken: Data) {
        #if DEBUG
            PushNotificationsInstallation.update(.registered(deviceToken: deviceToken))
        #endif
    }

    /// Shows why registering for remote notifications failed: call it from the app delegate's
    /// `application(_:didFailToRegisterForRemoteNotificationsWithError:)`. In release it does
    /// nothing.
    ///
    /// - Parameter error: The error, as the delegate method receives it.
    @MainActor
    public static func didFailToRegisterForRemoteNotifications(withError error: any Error) {
        #if DEBUG
            PushNotificationsInstallation.update(.failed(message: error.localizedDescription))
        #endif
    }
}
