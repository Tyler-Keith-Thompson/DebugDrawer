// iOS scales text with Dynamic Type, so the large-text snapshots run on the iOS simulator.
#if os(iOS) && !targetEnvironment(macCatalyst)
    @testable import DebugDrawerHangDetectorPlugin
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct HangsDynamicTypeSnapshotTests {
        @Test("The hangs stay readable at a large accessibility text size, the New tag below the duration")
        func hangs() throws {
            let opened = HangEvent(
                id: UUID(), date: Date(timeIntervalSince1970: 1_763_290_000), duration: .milliseconds(612),
                frames: [
                    "0 libsystem_kernel.dylib 0x00000001842b5f30 __semwait_signal + 8",
                    "1 Example 0x0000000100004a1c $s7Example13ExampleHangsO5blockyyFZ + 36"
                ],
                source: .detected, isSeen: false
            )
            let older = HangEvent(
                id: UUID(), date: Date(timeIntervalSince1970: 1_763_289_000), duration: .milliseconds(1840),
                frames: [], source: .metricKit, isSeen: true
            )
            let sut = HangsView(
                events: [opened, older], threshold: .constant(.milliseconds(250)), expanded: .constant(opened.id), ownImage: "Example",
                onOpen: { _ in }, onMarkAllSeen: {}, onClear: {}
            )
            .environment(\.locale, Locale(identifier: "en_US"))
            .environment(\.timeZone, try #require(TimeZone(identifier: "UTC")))
            .frame(width: 320, alignment: .leading)
            .padding()
            .background(Color(uiColor: .systemBackground))
            .environment(\.dynamicTypeSize, .accessibility3)
            // ImageRenderer draws UIKit-backed controls (the picker, the buttons) as placeholders,
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
