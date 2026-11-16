// iOS scales text with Dynamic Type, so the drawer's iOS snapshots run on the iOS simulator.
#if os(iOS)
    @testable import DebugDrawer
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    // Hosted in a window that is never shown and drawn from its layer, so the text fields,
    // switches and buttons draw as they do in the drawer rather than as placeholders; its height is
    // what the panel asks for at the drawer's width.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct DrawerPanelDynamicTypeSnapshotTests {
        @Test("On iOS the drawer with several plugins open reads in light, in dark and at a large accessibility size",
              arguments: [
                  (UIUserInterfaceStyle.light, DynamicTypeSize.large, "light"),
                  (UIUserInterfaceStyle.dark, DynamicTypeSize.large, "dark"),
                  (UIUserInterfaceStyle.light, DynamicTypeSize.accessibility3, "accessibility3")
              ])
        func panel(style: UIUserInterfaceStyle, typeSize: DynamicTypeSize, name: String) throws {
            let sut = DrawerFixturePanel()
                .frame(width: 340)
                .environment(\.dynamicTypeSize, typeSize)
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
            window.overrideUserInterfaceStyle = style
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
