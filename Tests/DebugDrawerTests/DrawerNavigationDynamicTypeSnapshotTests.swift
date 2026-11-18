// iOS scales text with Dynamic Type, so the drawer's iOS snapshots run on the iOS simulator.
#if os(iOS)
    @testable import DebugDrawer
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    // Hosted in a window that is never shown and drawn from its layer, so the text fields and
    // buttons draw as they do in the drawer rather than as placeholders. A plugin shown alone and
    // the compact list fill the panel's height, so each is drawn at a fixed size: the regular
    // panel's 316 points for the detail view, and an iPhone's 390 point window for the compact list.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct DrawerNavigationDynamicTypeSnapshotTests {
        @Test("On iOS a plugin shown alone reads at the default size and at a large accessibility size",
              arguments: [(DynamicTypeSize.large, "large"), (DynamicTypeSize.accessibility3, "accessibility3")])
        func detail(typeSize: DynamicTypeSize, name: String) throws {
            let size = CGSize(width: 316, height: 700)
            let sut = DrawerFixtureDetailPanel()
                .frame(width: size.width, height: size.height)
                .environment(\.dynamicTypeSize, typeSize)
            let controller = UIHostingController(rootView: sut)
            // No safe area: the window's status bar inset would push the panel down.
            controller.safeAreaRegions = []
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            let window = scene.map(UIWindow.init(windowScene:)) ?? UIWindow()
            window.frame = CGRect(origin: .zero, size: size)
            window.rootViewController = controller
            window.overrideUserInterfaceStyle = .light
            // UIKit-backed controls (the search field) read the size from the traits, not SwiftUI's environment.
            window.traitOverrides.preferredContentSizeCategory = UIContentSizeCategory(typeSize)
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

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: name)
        }

        @Test("On iOS the compact panel's list reads at the default size and at a large accessibility size",
              arguments: [(DynamicTypeSize.large, "large"), (DynamicTypeSize.accessibility3, "accessibility3")])
        func compact(typeSize: DynamicTypeSize, name: String) throws {
            let size = CGSize(width: 390, height: 800)
            let sut = DrawerFixtureCompactPanel()
                .frame(width: size.width, height: size.height)
                .environment(\.dynamicTypeSize, typeSize)
            let controller = UIHostingController(rootView: sut)
            // No safe area: the window's status bar inset would push the panel down.
            controller.safeAreaRegions = []
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            let window = scene.map(UIWindow.init(windowScene:)) ?? UIWindow()
            window.frame = CGRect(origin: .zero, size: size)
            window.rootViewController = controller
            window.overrideUserInterfaceStyle = .light
            // UIKit-backed controls (the search field) read the size from the traits, not SwiftUI's environment.
            window.traitOverrides.preferredContentSizeCategory = UIContentSizeCategory(typeSize)
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

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: name)
        }
    }
#endif
