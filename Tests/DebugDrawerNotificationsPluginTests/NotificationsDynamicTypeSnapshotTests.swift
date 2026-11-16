// iOS scales text with Dynamic Type, so the large-text snapshots run on the iOS simulator.
#if os(iOS)
    @testable import DebugDrawerNotificationsPlugin
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct NotificationsDynamicTypeSnapshotTests {
        @Test("The plugin stays readable at a large accessibility text size, the setting labels above their values and the buttons stacked")
        func notifications() {
            let snapshot = NotificationCenterSnapshot(
                settings: NotificationSettings(authorization: .notDetermined, items: [
                    .init(name: "Alerts", value: "Off"), .init(name: "Lock Screen", value: "Off")
                ]),
                pending: [ListedNotification(
                    id: "debugdrawer-5B1E", title: "Reminder", body: "Your cart is waiting",
                    trigger: .timeInterval(seconds: 5, repeats: false, next: nil)
                )],
                delivered: []
            )
            let sut = NotificationsView(
                registration: .failed(message: "no valid “aps-environment” entitlement string found for application"),
                center: .loaded(snapshot),
                authorizationRequest: .idle,
                sendState: .idle,
                draft: .constant(#"{"aps": {"alert": "Hi"}}"#),
                delay: .constant(.now),
                redaction: .standard,
                actions: NotificationsActions()
            )
            .frame(width: 320, alignment: .leading)
            .padding()
            .background(Color(uiColor: .systemBackground))
            .environment(\.dynamicTypeSize, .accessibility3)
            .environment(\.locale, Locale(identifier: "en_US_POSIX"))
            .environment(\.timeZone, TimeZone(identifier: "UTC") ?? .gmt)
            // ImageRenderer draws UIKit-backed controls (the editor, the picker, the buttons) as
            // placeholders, so the view is hosted in a window that is never shown and its layer is
            // rendered, at a fixed width and scale.
            let controller = UIHostingController(rootView: sut)
            let size = controller.sizeThatFits(in: CGSize(width: 352, height: 6000))
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            let window = scene.map(UIWindow.init(windowScene:)) ?? UIWindow()
            window.frame = CGRect(origin: .zero, size: size)
            window.rootViewController = controller
            window.overrideUserInterfaceStyle = .light
            window.isHidden = false
            controller.view.frame = window.bounds
            window.layoutIfNeeded()
            let format = UIGraphicsImageRendererFormat()
            format.scale = 2
            let actual = UIGraphicsImageRenderer(size: size, format: format).image { context in
                controller.view.layer.render(in: context.cgContext)
            }
            window.isHidden = true

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "accessibility3")
        }
    }
#endif
