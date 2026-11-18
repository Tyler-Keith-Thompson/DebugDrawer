// iOS scales text with Dynamic Type, so the large-text snapshots run on the iOS simulator, through
// SwiftPM (`just test-ios`); Bazel's iOS run links no SnapshotTesting, since its relative #filePath
// can't lead the simulator to the references (BAZEL_TESTED_PLATFORM_EXCLUDED_PACKAGES).
#if os(iOS) && !targetEnvironment(macCatalyst) && canImport(SnapshotTesting)
    @testable import DebugDrawerAppStateResetPlugin
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct AppStateResetDynamicTypeSnapshotTests {
        @Test("The plugin stays readable at an accessibility text size: each switch below its category, the summaries wrapping")
        func ready() throws {
            let sut = AppStateResetView(
                state: .ready(ResetPlanFixture.plan), selection: .constant([.userDefaults, .files, .cookies]), includesDebugDrawer: .constant(false),
                restartStyle: .quit, refresh: {}, reset: { _ in }
            )
            .environment(\.locale, Locale(identifier: "en_US"))
            .frame(width: 320, alignment: .leading)
            // No height proposed, as the drawer's scroll view proposes none.
            .fixedSize(horizontal: false, vertical: true)
            .padding()
            .background(Color(uiColor: .systemBackground))
            .environment(\.dynamicTypeSize, .accessibility3)
            // ImageRenderer draws UIKit-backed controls (the switches) as placeholders, so the view
            // is hosted in a window that is never shown and its layer is rendered, at a fixed width
            // and scale.
            let controller = UIHostingController(rootView: sut)
            // No safe area: the window's status bar inset would lay the view out shorter than it
            // measured, overlapping its rows.
            controller.safeAreaRegions = []
            let size = controller.sizeThatFits(in: CGSize(width: 352, height: 8000))
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
