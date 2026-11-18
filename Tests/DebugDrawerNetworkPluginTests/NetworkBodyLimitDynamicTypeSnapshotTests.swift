// iOS scales text with Dynamic Type, so the large-text snapshots run on the iOS simulator.
#if os(iOS)
    @testable import DebugDrawerNetworkPlugin
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    // At 316 points, the width of the drawer on an iPad and the narrowest it gets, at the default
    // text size and an accessibility one, so the note is seen to wrap there. The view is hosted in
    // a window that is never shown and its layer rendered, at a fixed width and scale, as the other
    // iOS snapshots are, since ImageRenderer draws UIKit-backed controls as placeholders.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct NetworkBodyLimitDynamicTypeSnapshotTests {
        @Test(
            "In an iPad's drawer, the note on a body the log cut short wraps without squeezing",
            arguments: [DynamicTypeSize.large, .accessibility3]
        )
        func truncatedDetail(size: DynamicTypeSize) {
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000), method: "GET",
                url: "https://cdn.example.com/v1/catalog.json", host: "cdn.example.com", path: "/v1/catalog.json",
                requestHeaders: [:], requestBody: nil, statusCode: 200, responseHeaders: ["Content-Type": "application/json"],
                responseBody: Data(repeating: UInt8(ascii: "a"), count: 1024), responseBodySize: 3_565_158, duration: 1.42,
                isComplete: true
            )
            let sut = NetworkRequestDetail(entry: entry, redaction: .standard, onMock: { _ in }, onResend: { _ in }, onEditAndResend: { _ in })
                .environment(\.locale, Locale(identifier: "en_US"))

            let controller = UIHostingController(rootView: sut
                .frame(width: 316, alignment: .leading)
                // No height proposed, as the drawer's scroll view proposes none.
                .fixedSize(horizontal: false, vertical: true)
                .background(Color(uiColor: .systemBackground))
                .environment(\.dynamicTypeSize, size))
            // No safe area: the window's status bar inset would lay the view out shorter than it
            // measured, overlapping its rows.
            controller.safeAreaRegions = []
            let measured = controller.sizeThatFits(in: CGSize(width: 316, height: 8000))
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
