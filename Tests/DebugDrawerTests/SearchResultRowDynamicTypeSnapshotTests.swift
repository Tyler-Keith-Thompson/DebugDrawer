// iOS scales text with Dynamic Type, so the large-text snapshots run on the iOS simulator.
#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit
    @testable import DebugDrawer

    private struct SnapshotOverridesPlugin: DebugDrawerPlugin {
        var title = "Accessibility Overrides"
        var icon = "accessibility"
        var body: some View { EmptyView() }
    }

    private struct SnapshotWebsiteDataPlugin: DebugDrawerPlugin {
        var title = "Website Data Storage"
        var icon = "externaldrive"
        var body: some View { EmptyView() }
    }

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct SearchResultRowDynamicTypeSnapshotTests {
        @Test("At the largest accessibility text size search result titles and plugin names wrap between words")
        func accessibility5() throws {
            let overrides = AnyDebugDrawerPlugin(SnapshotOverridesPlugin())
            let websiteData = AnyDebugDrawerPlugin(SnapshotWebsiteDataPlugin())
            let results: [DrawerSearchResult] = [
                .plugin(overrides),
                .action(DebugDrawerAction("Clear Expired Cookies") {}, in: websiteData),
                .action(DebugDrawerAction("Reset Every Override") {}, in: overrides)
            ]
            let sut = VStack(spacing: 0) {
                ForEach(Array(results.enumerated()), id: \.offset) { index, result in
                    SearchResultRow(result: result, isHighlighted: index == 1)
                }
            }
            // The drawer's own width.
            .frame(width: 340)
            .background(Color(uiColor: .systemBackground))
            .environment(\.dynamicTypeSize, .accessibility5)
            // Hosted in a window that is never shown and drawn from its layer, as the drawer draws
            // it; its height is what the rows ask for at this width.
            let controller = UIHostingController(rootView: sut)
            // No safe area: the window's status bar inset would lay the view out shorter than it
            // measured, overlapping its rows.
            controller.safeAreaRegions = []
            let fitted = controller.sizeThatFits(in: CGSize(width: 340, height: CGFloat.greatestFiniteMagnitude))
            let size = CGSize(width: 340, height: fitted.height.rounded(.up))
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            let window = scene.map(UIWindow.init(windowScene:)) ?? UIWindow()
            window.frame = CGRect(origin: .zero, size: size)
            window.rootViewController = controller
            window.overrideUserInterfaceStyle = .light
            window.isHidden = false
            controller.view.frame = window.bounds
            window.layoutIfNeeded()
            controller.view.layer.displayIfNeeded()
            let format = UIGraphicsImageRendererFormat()
            format.scale = 2
            let actual = UIGraphicsImageRenderer(size: size, format: format).image { context in
                controller.view.layer.render(in: context.cgContext)
            }
            window.isHidden = true

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "accessibility5")
        }

        @Test("At the default text size each search result keeps its one-line layout")
        func defaultSize() throws {
            let overrides = AnyDebugDrawerPlugin(SnapshotOverridesPlugin())
            let websiteData = AnyDebugDrawerPlugin(SnapshotWebsiteDataPlugin())
            let results: [DrawerSearchResult] = [
                .plugin(overrides),
                .action(DebugDrawerAction("Clear Expired Cookies") {}, in: websiteData),
                .action(DebugDrawerAction("Reset Every Override") {}, in: overrides)
            ]
            let sut = VStack(spacing: 0) {
                ForEach(Array(results.enumerated()), id: \.offset) { index, result in
                    SearchResultRow(result: result, isHighlighted: index == 1)
                }
            }
            // The drawer's own width.
            .frame(width: 340)
            .background(Color(uiColor: .systemBackground))
            .environment(\.dynamicTypeSize, .large)
            // Hosted in a window that is never shown and drawn from its layer, as the drawer draws
            // it; its height is what the rows ask for at this width.
            let controller = UIHostingController(rootView: sut)
            // No safe area: the window's status bar inset would lay the view out shorter than it
            // measured, overlapping its rows.
            controller.safeAreaRegions = []
            let fitted = controller.sizeThatFits(in: CGSize(width: 340, height: CGFloat.greatestFiniteMagnitude))
            let size = CGSize(width: 340, height: fitted.height.rounded(.up))
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            let window = scene.map(UIWindow.init(windowScene:)) ?? UIWindow()
            window.frame = CGRect(origin: .zero, size: size)
            window.rootViewController = controller
            window.overrideUserInterfaceStyle = .light
            window.isHidden = false
            controller.view.frame = window.bounds
            window.layoutIfNeeded()
            controller.view.layer.displayIfNeeded()
            let format = UIGraphicsImageRendererFormat()
            format.scale = 2
            let actual = UIGraphicsImageRenderer(size: size, format: format).image { context in
                controller.view.layer.render(in: context.cgContext)
            }
            window.isHidden = true

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "large")
        }
    }
#endif
