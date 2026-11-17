// The README's Deep Link example, verbatim, so the README cannot drift from the code. It lives
// here rather than in DebugDrawerTests, which links core alone.

#if DEBUG
    import DebugDrawer
    import DebugDrawerDeepLinkPlugin
    import Foundation
    import Testing

    /// The app's router: `onContinueUserActivity` hands it the activities the system continues.
    @MainActor
    final class Router {
        private(set) var path: [String] = []

        func handle(_ activity: NSUserActivity) {
            if let url = activity.webpageURL {
                path.append(url.path)
            }
        }
    }

    @MainActor
    @Suite("README examples")
    struct READMEExamplesTests {
        @Test("Deep links: universal links and user activities")
        func deepLinks() {
            let router = Router()

            #if DEBUG
            DebugDrawer.shared.installDeepLink(continueUserActivity: router.handle)
            #endif

            // Leave the shared drawer as the other suites expect it, within this one main-actor turn.
            let installed = DebugDrawer.shared.globalPlugins.contains { $0.id == "DeepLinkPlugin" }
            DebugDrawer.shared.unregisterGlobal(id: "DeepLinkPlugin")
            let activity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
            activity.webpageURL = URL(string: "https://example.com/orders/42")
            router.handle(activity)
            #expect(installed)
            #expect(router.path == ["/orders/42"])
        }
    }
#endif
