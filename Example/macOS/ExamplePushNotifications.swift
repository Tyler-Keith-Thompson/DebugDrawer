import AppKit
import UserNotifications

// The iOS example has its own copy of this file: each app is its own module, and the examples
// share no code.

/// Registers for remote notifications, which the app delegate's methods forward to the
/// Notifications plugin. On the Mac the push entitlement needs a provisioning profile, which the
/// example isn't signed with, so registering fails and the plugin shows why. It is
/// also the notification center's delegate, so a payload the drawer sends shows as a banner while
/// the app is in front, and it logs each notification the user opens.
@MainActor
final class ExamplePushNotifications: NSObject {
    /// The notification center's delegate, which it holds weakly.
    private static let shared = ExamplePushNotifications()

    /// Becomes the notification center's delegate and registers.
    static func register() {
        UNUserNotificationCenter.current().delegate = shared
        NSApplication.shared.registerForRemoteNotifications()
    }
}

extension ExamplePushNotifications: UNUserNotificationCenterDelegate {
    // The app decides how a notification shows while it is in front; this one shows each as a
    // banner, so a payload sent from the drawer is seen at once.
    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter, willPresent _: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound, .badge]
    }

    // The handler a pasted payload exercises: the Console plugin shows the line.
    nonisolated func userNotificationCenter(_: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let request = response.notification.request
        let keys = request.content.userInfo.keys.map(String.init(describing:)).sorted()
        print("Opened notification \(request.identifier) with userInfo keys \(keys)")
    }
}
