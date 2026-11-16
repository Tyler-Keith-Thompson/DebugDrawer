// iOS scales text with Dynamic Type, so the large-text snapshots run on the iOS simulator.
#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit
    @testable import DebugDrawer

    private struct SnapshotLibrariesPlugin: DebugDrawerPlugin {
        var title = "Loaded Libraries"
        var icon = "books.vertical"
        var body: some View { EmptyView() }
    }

    private struct SnapshotOverridesPlugin: DebugDrawerPlugin {
        var title = "Accessibility Overrides"
        var icon = "accessibility"
        var body: some View { EmptyView() }
    }

    private struct SnapshotDefaultsPlugin: DebugDrawerPlugin {
        var title = "User Defaults"
        var icon = "list.bullet.rectangle"
        var body: some View { EmptyView() }
    }

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct DrawerChromeDynamicTypeSnapshotTests {
        @Test("At the largest accessibility text size the header and long plugin titles wrap rather than truncate")
        func chrome() throws {
            let sut = VStack(spacing: 0) {
                DrawerHeader(isReportInProgress: false, createReport: {}, close: {})
                PluginSectionHeader(
                    plugin: AnyDebugDrawerPlugin(SnapshotLibrariesPlugin()),
                    isExpanded: true,
                    isPinned: true,
                    badge: 12,
                    isMovable: true,
                    toggle: {}
                )
                PluginSectionHeader(
                    plugin: AnyDebugDrawerPlugin(SnapshotOverridesPlugin()),
                    isExpanded: false,
                    isPinned: false,
                    badge: nil,
                    isMovable: true,
                    toggle: {}
                )
                PluginSectionHeader(
                    plugin: AnyDebugDrawerPlugin(SnapshotDefaultsPlugin()),
                    isExpanded: false,
                    isPinned: false,
                    badge: 3,
                    isMovable: true,
                    toggle: {}
                )
            }
            // The drawer's own width.
            .frame(width: 340)
            .background(Color(uiColor: .systemBackground))
            .environment(\.dynamicTypeSize, .accessibility5)
            // Hosted in a window that is never shown and drawn from its layer, so the buttons draw
            // as they do in the drawer; its height is what the chrome asks for at this width.
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
    }
#endif
