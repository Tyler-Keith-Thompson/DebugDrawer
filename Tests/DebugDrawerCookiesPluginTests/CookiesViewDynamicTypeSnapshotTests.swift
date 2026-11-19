// iOS scales text with Dynamic Type, so the large-text snapshots run on the iOS simulator.
#if os(iOS) && !targetEnvironment(macCatalyst)
    import DebugDrawer
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit
    @testable import DebugDrawerCookiesPlugin

    // The plugin's whole view, drawn from a transport that holds a fixed snapshot and drops every
    // command, so nothing reads a cookie store. ImageRenderer draws UIKit-backed controls (the
    // filter's text field) as placeholders, so the view is hosted in a window that is never shown
    // and its layer rendered, at a fixed width and scale, so the reference doesn't depend on which
    // simulator runs it.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct CookiesViewDynamicTypeSnapshotTests {
        @Test("In an iPad's drawer, the plugin keeps the count, buttons, filter and each cookie readable at a large accessibility text size")
        func cookies() {
            let snapshot = CookiesSnapshot(contents: .cookies([
                StoredCookie(
                    name: "session", value: "a1b2c3", domain: "api.example.com", path: "/", store: .urlSession,
                    isSecure: true, isHTTPOnly: true, expiresDate: nil
                ),
                StoredCookie(
                    name: "csrftoken", value: "x9y8z7", domain: ".web.example.com", path: "/", store: .webView,
                    isSecure: true, isHTTPOnly: false, expiresDate: nil
                )
            ]), filter: "")
            let sut = CookiesPluginView(transport: DebugDrawerPluginTransport(
                initial: snapshot, snapshots: AsyncStream { $0.finish() }, send: { _ in }
            ))
            let controller = UIHostingController(rootView: sut
                .frame(width: 316, alignment: .leading)
                // No height proposed, as the drawer's scroll view proposes none.
                .fixedSize(horizontal: false, vertical: true)
                .padding()
                .background(.background)
                .environment(\.dynamicTypeSize, .accessibility3))
            // No safe area: the window's status bar inset would lay the view out shorter than it
            // measured, overlapping its rows.
            controller.safeAreaRegions = []
            let measured = controller.sizeThatFits(in: CGSize(width: 348, height: 8000))
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            let window = scene.map(UIWindow.init(windowScene:)) ?? UIWindow()
            window.frame = CGRect(origin: .zero, size: measured)
            window.rootViewController = controller
            window.overrideUserInterfaceStyle = .light
            window.isHidden = false
            controller.view.frame = window.bounds
            window.layoutIfNeeded()
            let format = UIGraphicsImageRendererFormat()
            format.scale = 2

            let actual = UIGraphicsImageRenderer(size: measured, format: format).image { context in
                controller.view.layer.render(in: context.cgContext)
            }
            window.isHidden = true

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "accessibility3")
        }
    }
#endif
