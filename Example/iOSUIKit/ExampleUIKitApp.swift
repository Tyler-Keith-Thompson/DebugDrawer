import DebugDrawer
import DebugDrawerDeepLinkPlugin
import SwiftUI
import UIKit

// A UIKit app with a scene delegate of its own, for the Deep Link Tester with no handler: an
// activity it sends goes to `ExampleUIKitSceneDelegate.scene(_:continue:)`, as a universal link,
// a Handoff or a Spotlight result does in such an app.

@main
final class ExampleUIKitAppDelegate: UIResponder, UIApplicationDelegate {
    func application(_: UIApplication, didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        DebugDrawer.shared.installDeepLink()
        return true
    }

    func application(
        _: UIApplication, configurationForConnecting session: UISceneSession, options _: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: session.role)
        configuration.delegateClass = ExampleUIKitSceneDelegate.self
        return configuration
    }
}

/// Shows the app's one screen and records each activity the scene continues.
final class ExampleUIKitSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private let continued = ExampleUIKitContinuedActivity()

    func scene(_ scene: UIScene, willConnectTo _: UISceneSession, options _: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(rootView: ExampleUIKitContentView(continued: continued).debugDrawer())
        window.makeKeyAndVisible()
        self.window = window
        // A UIKit app attaches the drawer to its scene itself; `.debugDrawer()` on the hosted root
        // above also does, for its HUD and toasts, and a second attach of a scene does nothing.
        DebugDrawer.shared.attach(to: windowScene)
        // Launched with -OpenDebugDrawer, the window opens with the drawer open.
        if ProcessInfo.processInfo.arguments.contains("-OpenDebugDrawer"), !DebugDrawer.shared.isOpen {
            DebugDrawer.shared.toggle()
        }
    }

    func scene(_: UIScene, continue userActivity: NSUserActivity) {
        continued.record(userActivity)
    }
}

/// The activity the scene delegate continued last.
@MainActor
final class ExampleUIKitContinuedActivity: ObservableObject {
    /// "scene(_:continue:): https://example.com/path", or nil before the first.
    @Published private(set) var summary: String?

    func record(_ activity: NSUserActivity) {
        let userInfo = (activity.userInfo ?? [:])
            .map { ("\($0.key)", "\($0.value)") }
            .sorted { $0.0 < $1.0 }
            .map { "\($0) = \($1)" }
            .joined(separator: ", ")
        let detail = activity.webpageURL?.absoluteString ?? "\(activity.activityType) {\(userInfo)}"
        summary = "scene(_:continue:): \(detail)"
    }
}

/// The app's screen: what the scene delegate continued last, and a button for the drawer.
struct ExampleUIKitContentView: View {
    @ObservedObject var continued: ExampleUIKitContinuedActivity

    var body: some View {
        NavigationStack {
            List {
                Section("Deep Links") {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Last Continued Activity")
                        Text(continued.summary ?? "None")
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .navigationTitle("UIKit Example")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        DebugDrawer.shared.toggle()
                    } label: {
                        Label("Debug Drawer", systemImage: "ladybug")
                    }
                }
            }
        }
    }
}
