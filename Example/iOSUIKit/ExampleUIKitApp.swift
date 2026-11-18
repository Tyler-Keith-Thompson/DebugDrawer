import DebugDrawer
import DebugDrawerNotificationsPlugin
import UIKit

// A UIKit app with no SwiftUI root: a scene delegate, a navigation controller and a view
// controller of UIKit views, with no `.debugDrawer()` anywhere. The scene delegate attaches the
// drawer with `attach(to:)`, and the drawer shows every global plugin the SwiftUI example does.
// The Deep Link Tester is installed with no handler, so an activity it sends goes to the scene
// delegate's scene(_:continue:), as a universal link, a Handoff or a Spotlight result does in such
// an app.

@main
final class ExampleUIKitAppDelegate: UIResponder, UIApplicationDelegate {
    func application(_: UIApplication, didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        ExampleUIKitPlugins.install()
        return true
    }

    func application(
        _: UIApplication, configurationForConnecting session: UISceneSession, options _: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: session.role)
        configuration.delegateClass = ExampleUIKitSceneDelegate.self
        return configuration
    }

    func application(_: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushNotifications.didRegisterForRemoteNotifications(withDeviceToken: deviceToken)
    }

    func application(_: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        PushNotifications.didFailToRegisterForRemoteNotifications(withError: error)
    }
}

/// Shows the app's one screen, attaches the drawer to the scene, and shows each activity the scene
/// continues.
final class ExampleUIKitSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private let screen = ExampleUIKitViewController()

    func scene(_ scene: UIScene, willConnectTo _: UISceneSession, options _: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UINavigationController(rootViewController: screen)
        window.makeKeyAndVisible()
        self.window = window
        // A UIKit app attaches the drawer to its scene once the scene has connected.
        DebugDrawer.shared.attach(to: windowScene)
        // Launched with -OpenDebugDrawer, the window opens with the drawer open.
        if ProcessInfo.processInfo.arguments.contains("-OpenDebugDrawer"), !DebugDrawer.shared.isOpen {
            DebugDrawer.shared.toggle()
        }
    }

    func scene(_: UIScene, continue userActivity: NSUserActivity) {
        screen.showContinued(userActivity)
    }
}
