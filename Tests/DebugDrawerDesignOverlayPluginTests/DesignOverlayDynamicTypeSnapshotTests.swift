// iOS scales text with Dynamic Type, so the large-text snapshots run on the iOS simulator.
#if os(iOS)
    @testable import DebugDrawerDesignOverlayPlugin
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct DesignOverlayDynamicTypeSnapshotTests {
        @Test("The plugin stays readable at an accessibility text size: controls below their titles, buttons stacked")
        func showing() throws {
            let mockup = try Mockup(data: MockupFixture.png(width: 1290, height: 2796))
            var settings = DesignOverlaySettings()
            settings.offset = CGSize(width: 12, height: -4)
            let sut = DesignOverlayView(
                mockup: mockup, failure: nil, windowWidth: 430, settings: .constant(settings), isMoving: .constant(false),
                sources: .none, clear: {}
            )
            .frame(width: 320, alignment: .leading)
            // No height proposed, as the drawer's scroll view proposes none.
            .fixedSize(horizontal: false, vertical: true)
            .padding()
            .background(Color(uiColor: .systemBackground))
            .environment(\.dynamicTypeSize, .accessibility3)
            // ImageRenderer draws UIKit-backed controls (the switches, the slider, the pickers, the
            // steppers) as placeholders, so the view is hosted in a window that is never shown and
            // its layer is rendered, at a fixed width and scale.
            let controller = UIHostingController(rootView: sut)
            // No safe area: the window's status bar inset would lay the view out shorter than it
            // measured, overlapping its rows.
            controller.safeAreaRegions = []
            let size = controller.sizeThatFits(in: CGSize(width: 352, height: 6000))
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
