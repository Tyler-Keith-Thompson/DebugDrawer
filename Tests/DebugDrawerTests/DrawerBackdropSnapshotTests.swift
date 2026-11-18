// Only iOS draws the backdrop, so its snapshots run on the iOS simulator.
#if os(iOS) && !targetEnvironment(macCatalyst)
    @testable import DebugDrawer
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    // The compact panel over an app, as the drawer's window lays it out on an iPhone 17 (402 by 874
    // points, 62 of status bar and 34 of home indicator): the backdrop dims what the panel leaves of
    // the app, and the panel keeps its margin inside the safe area. Hosted in a window that is never
    // shown and drawn from its layer, so the search field draws as it does in the drawer.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct DrawerBackdropSnapshotTests {
        @Test("On iOS the compact panel dims the strips of the app it leaves, in light and in dark",
              arguments: [(UIUserInterfaceStyle.light, "light"), (UIUserInterfaceStyle.dark, "dark")])
        func compactBackdrop(style: UIUserInterfaceStyle, name: String) throws {
            let size = CGSize(width: 402, height: 874)
            let sut = ZStack {
                BackdropFixtureApp()
                DrawerBackdrop {}
                DrawerFixtureCompactPanel()
                    .drawerPanelSurface()
                    .padding(.drawerPanel(layout: .compact))
                    .padding(EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0))
            }
            .frame(width: size.width, height: size.height)
            let controller = UIHostingController(rootView: sut)
            // No safe area: the fixture insets the panel by an iPhone's own.
            controller.safeAreaRegions = []
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            let window = scene.map(UIWindow.init(windowScene:)) ?? UIWindow()
            window.frame = CGRect(origin: .zero, size: size)
            window.rootViewController = controller
            window.overrideUserInterfaceStyle = style
            window.traitOverrides.preferredContentSizeCategory = .large
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

    /// An app's screen behind the drawer: an inline title in the strip above the panel, over rows
    /// on a grouped background, so the dimmed strips show the app through them.
    private struct BackdropFixtureApp: View {
        var body: some View {
            VStack(spacing: 0) {
                Text("Orders")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 70)
                    .padding(.bottom, 16)
                ForEach(["#1042 Shipped", "#1041 Packing", "#1040 Delivered", "#1039 Delivered"], id: \.self) { row in
                    Text(row)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .overlay(alignment: .bottom) { Divider() }
                }
                Spacer(minLength: 0)
            }
            .background(Color(uiColor: .systemGroupedBackground))
        }
    }
#endif
