#if DEBUG
    #if os(macOS)
        import AppKit
    #elseif os(iOS)
        import UIKit
    #endif
    @testable import DebugDrawerDeepLinkPlugin
    import Foundation
    import Testing

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct UserActivityDeliveringTests {
        @Test("A registered handler receives the activity itself")
        func handler() {
            var received: [NSUserActivity] = []
            let sut = _UserActivityDelivering(handler: { received.append($0) })
            let activity = NSUserActivity(activityType: "com.example.app.compose")

            let actual = sut.deliver(activity)

            #expect(actual == .handler)
            #expect(received.count == 1)
            #expect(received.first === activity)
        }

        #if os(macOS)
            @Test("With no handler, the Mac app delegate's application(_:continue:restorationHandler:) receives the activity")
            func applicationDelegate() {
                let delegate = ContinuingApplicationDelegate(accepts: true)
                let activity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)

                let actual = _UserActivityDelivering.continue(activity, application: .shared, applicationDelegate: delegate)

                #expect(actual == .applicationDelegate)
                #expect(delegate.received.count == 1)
                #expect(delegate.received.first === activity)
            }

            @Test("An app delegate that returns false is reported as declining the activity")
            func declined() {
                let delegate = ContinuingApplicationDelegate(accepts: false)

                let actual = _UserActivityDelivering.continue(
                    NSUserActivity(activityType: "com.example.app.compose"), application: .shared, applicationDelegate: delegate
                )

                #expect(actual == .declined)
            }

            @Test("An app delegate without the method, or no app delegate, leaves the activity unhandled")
            func unhandled() {
                let activity = NSUserActivity(activityType: "com.example.app.compose")

                let withoutMethod = _UserActivityDelivering.continue(activity, application: .shared, applicationDelegate: PlainApplicationDelegate())
                let withoutDelegate = _UserActivityDelivering.continue(activity, application: .shared, applicationDelegate: nil)

                #expect(withoutMethod == .unhandled)
                #expect(withoutDelegate == .unhandled)
            }
        #elseif os(iOS)
            // A UIScene can't be made outside UIKit, and the iOS test host connects none, so the
            // scene delegate's path is shown in the UIKit example app (Example/iOSUIKit), which
            // installs the plugin with no handler.
            @Test("With no handler and no scene delegate that continues activities, the app delegate receives the activity")
            func applicationDelegate() {
                let applicationDelegate = ContinuingApplicationDelegate(accepts: true)
                let activity = NSUserActivity(activityType: "com.example.app.compose")

                let actual = _UserActivityDelivering.continue(activity, scenes: [], application: .shared, applicationDelegate: applicationDelegate)

                #expect(actual == .applicationDelegate)
                #expect(applicationDelegate.received.first === activity)
            }

            @Test("With no scene delegate or app delegate method, the activity is unhandled; one returning false declines it")
            func unhandled() {
                let activity = NSUserActivity(activityType: "com.example.app.compose")

                let unhandled = _UserActivityDelivering.continue(activity, scenes: [], application: .shared, applicationDelegate: nil)
                let declined = _UserActivityDelivering.continue(
                    activity, scenes: [], application: .shared, applicationDelegate: ContinuingApplicationDelegate(accepts: false)
                )

                #expect(unhandled == .unhandled)
                #expect(declined == .declined)
            }
        #endif
    }

    #if os(macOS)
        /// An app delegate that continues activities, keeping each, and accepts or declines them.
        @MainActor
        final class ContinuingApplicationDelegate: NSObject, NSApplicationDelegate {
            let accepts: Bool
            private(set) var received: [NSUserActivity] = []

            init(accepts: Bool) {
                self.accepts = accepts
            }

            func application(
                _ application: NSApplication,
                continue userActivity: NSUserActivity,
                restorationHandler: @escaping ([any NSUserActivityRestoring]) -> Void
            ) -> Bool {
                received.append(userActivity)
                return accepts
            }
        }

        /// An app delegate that doesn't continue activities.
        final class PlainApplicationDelegate: NSObject, NSApplicationDelegate {}
    #elseif os(iOS)
        /// An app delegate that continues activities, keeping each, and accepts or declines them.
        final class ContinuingApplicationDelegate: UIResponder, UIApplicationDelegate {
            let accepts: Bool
            private(set) var received: [NSUserActivity] = []

            init(accepts: Bool) {
                self.accepts = accepts
            }

            func application(
                _ application: UIApplication,
                continue userActivity: NSUserActivity,
                restorationHandler: @escaping ([any UIUserActivityRestoring]?) -> Void
            ) -> Bool {
                received.append(userActivity)
                return accepts
            }
        }
    #endif
#endif
