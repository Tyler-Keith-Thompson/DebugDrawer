// iOS scales text with Dynamic Type, so the large-text snapshots run on the iOS simulator.
#if os(iOS) && !targetEnvironment(macCatalyst)
    @testable import DebugDrawerLocationPlugin
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    // ImageRenderer draws UIKit-backed controls (the menus) as placeholders, so the section is
    // hosted in a window that is never shown and its layer is rendered, at a fixed width and scale,
    // at the default text size and at a large accessibility one.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct RouteDynamicTypeSnapshotTests {
        @Test("Stopped, the Route section stays readable at the default and an accessibility text size", arguments: [
            DynamicTypeSize.large, .accessibility3
        ])
        func idle(size: DynamicTypeSize) throws {
            let sut = RouteSection(
                routes: Route.samples, selection: .constant("sample:Apple Park Loop"), speed: .constant(.times1), playback: .stopped,
                importFailure: nil, actions: RouteActions()
            )
            .frame(width: 316, alignment: .leading)
            // No height proposed, as the drawer's scroll view proposes none.
            .fixedSize(horizontal: false, vertical: true)
            .padding()
            .background(Color(uiColor: .systemBackground))
            .environment(\.dynamicTypeSize, size)
            let controller = UIHostingController(rootView: sut)
            // No safe area: the window's status bar inset would lay the view out shorter than it
            // measured, overlapping its rows.
            controller.safeAreaRegions = []
            let fitting = controller.sizeThatFits(in: CGSize(width: 348, height: 6000))
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            let window = scene.map(UIWindow.init(windowScene:)) ?? UIWindow()
            window.frame = CGRect(origin: .zero, size: fitting)
            window.rootViewController = controller
            window.overrideUserInterfaceStyle = .light
            window.isHidden = false
            controller.view.frame = window.bounds
            window.layoutIfNeeded()
            let format = UIGraphicsImageRendererFormat()
            format.scale = 2
            let actual = UIGraphicsImageRenderer(size: fitting, format: format).image { context in
                controller.view.layer.render(in: context.cgContext)
            }
            window.isHidden = true

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(size)")
        }

        @Test("Playing, the Route section stays readable at the default and an accessibility text size", arguments: [
            DynamicTypeSize.large, .accessibility3
        ])
        func playing(size: DynamicTypeSize) throws {
            let sut = RouteSection(
                routes: Route.samples, selection: .constant("sample:Apple Park Loop"), speed: .constant(.times5),
                playback: .playing(delivered: 7), importFailure: nil, actions: RouteActions()
            )
            .frame(width: 316, alignment: .leading)
            // No height proposed, as the drawer's scroll view proposes none.
            .fixedSize(horizontal: false, vertical: true)
            .padding()
            .background(Color(uiColor: .systemBackground))
            .environment(\.dynamicTypeSize, size)
            let controller = UIHostingController(rootView: sut)
            // No safe area: the window's status bar inset would lay the view out shorter than it
            // measured, overlapping its rows.
            controller.safeAreaRegions = []
            let fitting = controller.sizeThatFits(in: CGSize(width: 348, height: 6000))
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            let window = scene.map(UIWindow.init(windowScene:)) ?? UIWindow()
            window.frame = CGRect(origin: .zero, size: fitting)
            window.rootViewController = controller
            window.overrideUserInterfaceStyle = .light
            window.isHidden = false
            controller.view.frame = window.bounds
            window.layoutIfNeeded()
            let format = UIGraphicsImageRendererFormat()
            format.scale = 2
            let actual = UIGraphicsImageRenderer(size: fitting, format: format).image { context in
                controller.view.layer.render(in: context.cgContext)
            }
            window.isHidden = true

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(size)")
        }
    }
#endif
