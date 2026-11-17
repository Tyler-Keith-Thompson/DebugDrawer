// iOS scales text with Dynamic Type, so the large-text snapshots run on the iOS simulator.
#if os(iOS)
    @testable import DebugDrawerScreenRecordingPlugin
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct ScreenRecordingDynamicTypeSnapshotTests {
        @Test("The plugin stays readable at an accessibility text size: Show Touches, each recording's buttons stacked")
        func saved() throws {
            let newest = Recording(
                url: URL(filePath: "/tmp/Screen Recording 2025-11-16T10-47-00Z.mov"),
                started: Date(timeIntervalSince1970: 1_763_290_020), duration: .seconds(12), byteCount: 3_400_000
            )
            let sut = ScreenRecordingView(
                state: .finished(newest.url), recordings: [newest], includedInReport: [newest.id], capacity: 5,
                showsTouches: .constant(true), start: {}, stop: {}, delete: { _ in }, setIncludedInReport: { _, _ in }
            )
            .environment(\.locale, Locale(identifier: "en_US"))
            .environment(\.timeZone, try #require(TimeZone(identifier: "UTC")))
            .frame(width: 320, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding()
            .background(Color(uiColor: .systemBackground))
            .environment(\.dynamicTypeSize, .accessibility3)
            // ImageRenderer draws UIKit-backed controls (the switch, the buttons) as placeholders,
            // so the view is hosted in a window that is never shown and its layer is rendered, at a
            // fixed width and scale.
            let controller = UIHostingController(rootView: sut)
            // No safe area: the window's status bar inset would lay the view out shorter than it
            // measured, overlapping its rows.
            controller.safeAreaRegions = []
            let size = controller.sizeThatFits(in: CGSize(width: 352, height: 4000))
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
