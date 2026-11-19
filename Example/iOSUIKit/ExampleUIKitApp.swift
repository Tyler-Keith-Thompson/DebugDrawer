import DebugDrawer
import DebugDrawerNotificationsPlugin
import ExamplePlugins
import ExampleTestBench
import UIKit

// A UIKit app with no SwiftUI root: a scene delegate, a navigation controller and a view
// controller of UIKit views, with no `.debugDrawer()` anywhere. The scene delegate attaches the
// drawer with `attach(to:)`, and the drawer shows every global plugin the SwiftUI example does.
// The Deep Link Tester is installed with no continueUserActivity handler, so an activity it sends
// goes to the scene delegate's scene(_:continue:), as a universal link, a Handoff or a Spotlight
// result does in such an app. A URL it opens goes to the scene delegate's own routing, which
// scene(_:openURLContexts:) uses for a URL the system opens.

@main
final class ExampleUIKitAppDelegate: UIResponder, UIApplicationDelegate {
    func application(_: UIApplication, didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        ExamplePlugins.install(openURL: { url in
            UIApplication.shared.connectedScenes
                .compactMap { $0.delegate as? ExampleUIKitSceneDelegate }
                .first?.route(url, via: "openURL") ?? false
        })
        // Serves a sidecar's sessions; the screen shows a banner while one is open.
        ExampleSidecar.install()
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

/// Shows the app's one screen, attaches the drawer to the scene, and shows each URL the scene
/// opens and activity it continues.
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
        // Launched with -RunTestBench, runs those test bench actions, then opens the drawer at the
        // plugin -OpenDebugDrawerPlugin names.
        TestBench.runFromLaunchArguments()
    }

    func scene(_: UIScene, continue userActivity: NSUserActivity) {
        screen.showContinued(userActivity)
    }

    func scene(_: UIScene, openURLContexts contexts: Set<UIOpenURLContext>) {
        for context in contexts {
            route(context.url, via: "scene(_:openURLContexts:)")
        }
    }

    /// Takes `url` when it is of the app's own scheme, which Info.plist declares, and says
    /// whether it did.
    @discardableResult
    func route(_ url: URL, via route: String) -> Bool {
        guard url.scheme?.lowercased() == "debugdrawer-example-uikit" else { return false }
        screen.showOpened(url, via: route)
        return true
    }
}
