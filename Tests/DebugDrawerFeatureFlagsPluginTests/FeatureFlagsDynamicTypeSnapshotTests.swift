// iOS scales text with Dynamic Type, so the large-text snapshots run on the iOS simulator.
#if os(iOS) && !targetEnvironment(macCatalyst)
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit
    @testable import DebugDrawerFeatureFlagsPlugin

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct FeatureFlagsDynamicTypeSnapshotTests {
        @Test("The flags stay readable at a large accessibility text size, titles above fields")
        func flags() {
            let rows = [
                FeatureFlagRowState(
                    FeatureFlag(key: "new-checkout", liveValue: .bool(false), title: "New checkout", detail: "The one-page payment sheet"),
                    currentValue: .bool(true),
                    override: .bool(true)
                ),
                FeatureFlagRowState(
                    FeatureFlag(key: "discount", liveValue: .number(0.1), title: "Discount"),
                    currentValue: .number(0.1),
                    override: nil
                ),
                FeatureFlagRowState(FeatureFlag(key: "theme", liveValue: .string("light")), currentValue: .string("dark"), override: .string("dark"))
            ]
            let sut = FeatureFlagsView(
                rows: rows, overrideCount: 2, query: .constant(""), isOverriddenOnly: .constant(false),
                onOverride: { _, _ in }, onClear: { _ in }, onClearAll: {}, onRefresh: {}
            )
            .frame(width: 320, alignment: .leading)
            .padding()
            .background(Color(uiColor: .systemBackground))
            .environment(\.dynamicTypeSize, .accessibility3)
            // ImageRenderer draws UIKit-backed controls (the switches and text fields) as
            // placeholders, so the view is hosted in a window that is never shown and its layer is
            // rendered, at a fixed width and scale.
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
