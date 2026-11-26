import Foundation
#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// The app delegate, which owns the host and hands it what APNs answers: the device token, which
/// only the delegate hears and which the push registration capability serves to a sidecar during
/// its session. The app registers for remote notifications as it launches.
@MainActor
final class ExampleReceiverAppDelegate: NSObject, ObservableObject {
    let host: ExampleReceiverHost

    override init() {
        do {
            host = try ExampleReceiverHost()
        } catch {
            // The host throws only for its own constants (the app state's field keys, the reset
            // categories, the capacities and thresholds it passes), which are valid; a change that
            // broke one should stop the example at launch, where it is seen.
            fatalError("The example's receiver host refused its own configuration: \(error)")
        }
        super.init()
    }
}

#if os(macOS)
    extension ExampleReceiverAppDelegate: NSApplicationDelegate {
        func applicationDidFinishLaunching(_ notification: Notification) {
            NSApplication.shared.registerForRemoteNotifications()
        }

        func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
            host.didRegisterForRemoteNotifications(withDeviceToken: deviceToken)
        }

        func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
            host.didFailToRegisterForRemoteNotifications(withError: error)
        }
    }
#else
    extension ExampleReceiverAppDelegate: UIApplicationDelegate {
        func application(
            _ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
        ) -> Bool {
            application.registerForRemoteNotifications()
            return true
        }

        func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
            host.didRegisterForRemoteNotifications(withDeviceToken: deviceToken)
        }

        func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
            host.didFailToRegisterForRemoteNotifications(withError: error)
        }
    }
#endif
