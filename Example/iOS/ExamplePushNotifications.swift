// The macOS example has its own copy of this file: each app is its own module, and the examples
// share no code. `bazel build //...` also compiles this library for the Mac, where UIKit doesn't
// exist, so that build leaves the delegate out.
#if canImport(UIKit)
    import DebugDrawerNotificationsPlugin
    import UIKit
    #if DEBUG
        import UserNotifications
    #endif

    /// The app delegate a SwiftUI app adds for push: registers for remote notifications and forwards
    /// the token, or the failure, to the Notifications plugin. The app's entitlements declare
    /// `aps-environment`, so the simulator gives it a token. In debug builds it is also the
    /// notification center's delegate, so a payload the drawer sends shows as a banner while the app
    /// is in front, and it logs each notification the user opens.
    final class ExampleAppDelegate: NSObject, UIApplicationDelegate {
        func application(_ application: UIApplication, didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
            #if DEBUG
                UNUserNotificationCenter.current().delegate = self
            #endif
            application.registerForRemoteNotifications()
            return true
        }

        func application(_: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
            PushNotifications.didRegisterForRemoteNotifications(withDeviceToken: deviceToken)
        }

        func application(_: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
            PushNotifications.didFailToRegisterForRemoteNotifications(withError: error)
        }
    }

    #if DEBUG
        extension ExampleAppDelegate: UNUserNotificationCenterDelegate {
            /// The app decides how a notification shows while it is in front; this one shows each as a
            /// banner, so a payload sent from the drawer is seen at once.
            nonisolated func userNotificationCenter(
                _: UNUserNotificationCenter, willPresent _: UNNotification
            ) async -> UNNotificationPresentationOptions {
                [.banner, .list, .sound, .badge]
            }

            /// The handler a pasted payload exercises: the Console plugin shows the line.
            nonisolated func userNotificationCenter(_: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
                let request = response.notification.request
                let keys = request.content.userInfo.keys.map(String.init(describing:)).sorted()
                print("Opened notification \(request.identifier) with userInfo keys \(keys)")
            }
        }
    #endif
#endif
