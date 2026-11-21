// iOS draws the row's controls with UIKit and scales text with Dynamic Type, so these run on the
// iOS simulator.
#if os(iOS) && !targetEnvironment(macCatalyst) && canImport(SnapshotTesting)
    import DebugDrawer
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    // ImageRenderer draws UIKit-backed controls (switches, sliders, steppers) as placeholders, so
    // the rows are hosted in a window that is never shown and its layer is rendered, at a fixed
    // width and scale, once in light and once in dark.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct DrawerRowControlSnapshotTests {
        @Test("Rows with an icon and a switch, a slider or a stepper keep the icon on the title's line, the control beside it")
        func iconRowsWithControls() {
            let sut = VStack(alignment: .leading, spacing: 0) {
                DebugDrawerRow("Show touches", systemImage: "hand.tap", isOn: .constant(true))
                DebugDrawerRow("Opacity", systemImage: "circle.lefthalf.filled") {
                    Slider(value: .constant(0.5))
                }
                DebugDrawerRow("Offset", systemImage: "arrow.left.and.right") {
                    Stepper("Offset", value: .constant(0), in: -10...10)
                }
            }
            .frame(width: 320, alignment: .leading)
            .padding()
            .background(Color(uiColor: .systemBackground))
            let controller = UIHostingController(rootView: sut)
            // No safe area: the window's status bar inset would lay the view out shorter than it
            // measured, overlapping its rows.
            controller.safeAreaRegions = []
            let size = controller.sizeThatFits(in: CGSize(width: 352, height: 2000))
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            let window = scene.map(UIWindow.init(windowScene:)) ?? UIWindow()
            window.frame = CGRect(origin: .zero, size: size)
            window.rootViewController = controller
            window.isHidden = false
            controller.view.frame = window.bounds
            let format = UIGraphicsImageRendererFormat()
            format.scale = 2
            let styles: [(name: String, style: UIUserInterfaceStyle)] = [("light", .light), ("dark", .dark)]

            for (name, style) in styles {
                window.overrideUserInterfaceStyle = style
                window.layoutIfNeeded()
                let actual = UIGraphicsImageRenderer(size: size, format: format).image { context in
                    controller.view.layer.render(in: context.cgContext)
                }

                assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: name)
            }
            window.isHidden = true
        }

        @Test("At a large accessibility text size, rows with an icon and a control keep the icon on the title's line and move the control below")
        func iconRowsWithControlsAtAccessibilitySize() {
            let sut = VStack(alignment: .leading, spacing: 0) {
                DebugDrawerRow("Show touches", systemImage: "hand.tap", isOn: .constant(true))
                DebugDrawerRow("Opacity", systemImage: "circle.lefthalf.filled") {
                    Slider(value: .constant(0.5))
                }
                DebugDrawerRow("Offset", systemImage: "arrow.left.and.right") {
                    Stepper("Offset", value: .constant(0), in: -10...10)
                }
            }
            .frame(width: 320, alignment: .leading)
            .padding()
            .background(Color(uiColor: .systemBackground))
            .environment(\.dynamicTypeSize, .accessibility3)
            let controller = UIHostingController(rootView: sut)
            // No safe area: the window's status bar inset would lay the view out shorter than it
            // measured, overlapping its rows.
            controller.safeAreaRegions = []
            let size = controller.sizeThatFits(in: CGSize(width: 352, height: 2000))
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            let window = scene.map(UIWindow.init(windowScene:)) ?? UIWindow()
            window.frame = CGRect(origin: .zero, size: size)
            window.rootViewController = controller
            window.isHidden = false
            controller.view.frame = window.bounds
            let format = UIGraphicsImageRendererFormat()
            format.scale = 2
            let styles: [(name: String, style: UIUserInterfaceStyle)] = [("light", .light), ("dark", .dark)]

            for (name, style) in styles {
                window.overrideUserInterfaceStyle = style
                window.layoutIfNeeded()
                let actual = UIGraphicsImageRenderer(size: size, format: format).image { context in
                    controller.view.layer.render(in: context.cgContext)
                }

                assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "accessibility3-\(name)")
            }
            window.isHidden = true
        }
    }
#endif
