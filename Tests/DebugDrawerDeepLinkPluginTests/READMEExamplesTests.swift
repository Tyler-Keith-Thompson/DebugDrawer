// The README's Deep Link example, verbatim, so the README cannot drift from the code. It lives
// here rather than in DebugDrawerTests, which links core alone.

#if DEBUG
    import DebugDrawer
    import DebugDrawerDeepLinkPlugin
    import Foundation
    import Testing

    /// The app's router: `onOpenURL` and `onContinueUserActivity` hand it the links the system opens.
    @MainActor
    final class Router {
        private(set) var path: [String] = []

        func handle(_ activity: NSUserActivity) {
            if let url = activity.webpageURL {
                path.append(url.path)
            }
        }

        func open(_ url: URL) -> Bool {
            guard url.scheme == "myapp" else { return false }
            path.append(url.path)
            return true
        }
    }

    // Installing configures DeepLinkModel.shared, so this runs one at a time with the other tests
    // that install (DeepLinkSharedModelTests).
    extension DeepLinkSharedModelTests {
        @MainActor
        @Suite("README examples")
        struct READMEExamplesTests {
            @Test("Deep links: URLs, universal links and user activities")
            func deepLinks() throws {
                let router = Router()

                DebugDrawer.shared.installDeepLink(
                    presets: DeepLinkPreset.bundleURLSchemes + [DeepLinkPreset("Order 42", url: URL(string: "myapp://orders/42")!)],
                    continueUserActivity: router.handle,
                    openURL: router.open
                )

                // Leave the shared drawer as the other suites expect it, within this one main-actor turn.
                let installed = DebugDrawer.shared.globalPlugins.contains { $0.id == "DeepLinkPlugin" }
                DebugDrawer.shared.unregisterGlobal(id: "DeepLinkPlugin")
                let activity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
                activity.webpageURL = URL(string: "https://example.com/orders/42")
                router.handle(activity)
                let opened = try router.open(#require(URL(string: "myapp://orders/7")))
                let declined = try router.open(#require(URL(string: "other://orders/8")))
                #expect(installed)
                #expect(opened)
                #expect(!declined)
                // In myapp://orders/7, orders is the host.
                #expect(router.path == ["/orders/42", "/7"])
            }
        }
    }
#endif
