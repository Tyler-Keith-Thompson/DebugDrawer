// iOS scales text with Dynamic Type, so the large-text snapshots run on the iOS simulator.
#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit
    @testable import DebugDrawerViewInspectorPlugin

    // ImageRenderer draws UIKit-backed controls (text fields, pickers, switches) as placeholders,
    // so each view is hosted in a window that is never shown and its layer rendered, at a fixed
    // width and scale, so the reference doesn't depend on which simulator runs it.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct ViewInspectorDynamicTypeSnapshotTests {
        @Test("The render counts stay readable at the default and an accessibility text size", arguments: [DynamicTypeSize.large, .accessibility3])
        func renderCounts(size: DynamicTypeSize) throws {
            let entries = [
                RenderTracker.Entry(id: "FeedView", count: 24),
                RenderTracker.Entry(id: "AvatarView", count: 7),
                RenderTracker.Entry(id: "SettingsView", count: 2)
            ]
            let sut = RenderCountList(entries: entries) {}
            let controller = UIHostingController(rootView: VStack(spacing: 0) { sut }
                .frame(width: 320, alignment: .leading)
                // No height proposed, as the drawer's scroll view proposes none.
                .fixedSize(horizontal: false, vertical: true)
                .padding()
                .background(.background)
                .environment(\.dynamicTypeSize, size))
            // No safe area: the window's status bar inset would lay the view out shorter than it
            // measured, overlapping its rows.
            controller.safeAreaRegions = []
            let measured = controller.sizeThatFits(in: CGSize(width: 352, height: 8000))
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

        @Test("A hierarchy row stays readable at a large accessibility text size")
        func hierarchyRow() throws {
            let node = ViewNode(
                className: "NSButton", frame: CGRect(x: 0, y: 0, width: 88, height: 32),
                accessibilityLabel: "Save", accessibilityRole: "AXButton", isHidden: false, alpha: 0.5,
                hasClipping: true, cornerRadius: 6, backgroundColor: "#0A84FF", constraintCount: 4,
                subviewCount: 0, children: []
            )
            let sut = ViewNodeRow(node: node, depth: 0, filter: "")
            let controller = UIHostingController(rootView: sut
                .frame(width: 320, alignment: .leading)
                // No height proposed, as the drawer's scroll view proposes none.
                .fixedSize(horizontal: false, vertical: true)
                .padding()
                .background(.background)
                .environment(\.dynamicTypeSize, .accessibility3))
            // No safe area: the window's status bar inset would lay the view out shorter than it
            // measured, overlapping its rows.
            controller.safeAreaRegions = []
            let measured = controller.sizeThatFits(in: CGSize(width: 352, height: 8000))
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
