// iOS scales text with Dynamic Type, so the large-text snapshots run on the iOS simulator.
#if os(iOS) && !targetEnvironment(macCatalyst)
    import DebugDrawer
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit
    @testable import DebugDrawerNetworkPlugin

    // The plugin's whole view, drawn from a transport that holds a fixed snapshot and drops every
    // command, at the drawer's width on an iPad. ImageRenderer draws UIKit-backed controls (the
    // filter's text field) as placeholders, so the view is hosted in a window that is never shown
    // and its layer rendered, at a fixed width and scale.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct NetworkViewDynamicTypeSnapshotTests {
        @Test(
            "In an iPad's drawer, the request list grows with the text size, so it holds as many requests at a large accessibility size",
            arguments: [DynamicTypeSize.large, .accessibility3]
        )
        func requests(size: DynamicTypeSize) {
            let started = Date(timeIntervalSince1970: 1_800_000_000)
            var snapshot = NetworkSnapshot()
            snapshot.log.captured = (0 ..< 20).map { index in
                NetworkEntry(
                    timestamp: started.addingTimeInterval(Double(index)), method: index.isMultiple(of: 3) ? "POST" : "GET",
                    url: "https://shop.example.com/api/items/\(index)", host: "shop.example.com", path: "/api/items/\(index)",
                    requestHeaders: [:], requestBody: nil, statusCode: index.isMultiple(of: 5) ? 404 : 200, isComplete: true
                )
            }
            let sut = NetworkPluginView(transport: DebugDrawerPluginTransport(
                initial: snapshot, snapshots: AsyncStream { $0.finish() }, send: { _ in }
            ))
            .environment(\.locale, Locale(identifier: "en_US"))
            .environment(\.timeZone, .gmt)
            let controller = UIHostingController(rootView: sut
                .frame(width: 316, alignment: .leading)
                // No height proposed, as the drawer's scroll view proposes none.
                .fixedSize(horizontal: false, vertical: true)
                .padding()
                .background(.background)
                .environment(\.dynamicTypeSize, size))
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

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: size == .large ? "large" : "accessibility3")
        }
    }
#endif
