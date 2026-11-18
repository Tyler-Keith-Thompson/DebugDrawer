// iOS scales text with Dynamic Type, so the large-text snapshots run on the iOS simulator.
#if os(iOS) && !targetEnvironment(macCatalyst)
    @testable import DebugDrawerAnalyticsPlugin
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct AnalyticsDynamicTypeSnapshotTests {
        @Test("The events stay readable at an accessibility text size: time below name, detail labels above values, buttons stacked")
        func events() throws {
            let opened = AnalyticsEvent(
                id: 2, timestamp: Date(timeIntervalSince1970: 1_763_290_000.25), name: "checkout_completed",
                properties: ["plan": "pro", "seats": 3, "items": ["sku-1", "sku-2"]],
                source: "Segment"
            )
            let other = AnalyticsEvent(id: 1, timestamp: Date(timeIntervalSince1970: 1_763_289_990), name: "app_opened", properties: [:], source: nil)
            let sut = AnalyticsEventsView(
                events: [opened, other], capacity: 1000, query: .constant(""), selected: .constant(opened.id),
                redaction: .standard, onClear: {}
            )
            .environment(\.locale, Locale(identifier: "en_US"))
            .environment(\.timeZone, try #require(TimeZone(identifier: "UTC")))
            .frame(width: 320, alignment: .leading)
            // No height proposed, as the drawer's scroll view proposes none: offered the
            // window's height, the list's scroll view would grow to its tallest.
            .fixedSize(horizontal: false, vertical: true)
            .padding()
            .background(Color(uiColor: .systemBackground))
            .environment(\.dynamicTypeSize, .accessibility3)
            // ImageRenderer draws UIKit-backed controls (the field, the buttons) as placeholders,
            // so the view is hosted in a window that is never shown and its layer is rendered, at a
            // fixed width and scale.
            let controller = UIHostingController(rootView: sut)
            // No safe area: the window's status bar inset would lay the view out shorter than it
            // measured, overlapping its rows.
            controller.safeAreaRegions = []
            let size = controller.sizeThatFits(in: CGSize(width: 352, height: 4000))
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
