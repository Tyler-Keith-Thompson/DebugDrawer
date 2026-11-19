// iOS scales text with Dynamic Type, so the large-text snapshots run on the iOS simulator.
#if os(iOS) && !targetEnvironment(macCatalyst)
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit
    @testable import DebugDrawerConsolePlugin

    // The lines' well at the drawer's width on an iPad, with no height proposed, as in the drawer.
    // ImageRenderer draws a UIViewRepresentable as a placeholder, so the view is hosted in a window
    // that is never shown and its layer rendered, at a fixed width and scale.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct ConsoleLinesWellDynamicTypeSnapshotTests {
        @Test(
            "In an iPad's drawer, the lines' well grows with the text size, so it holds as many lines at a large accessibility size",
            arguments: [DynamicTypeSize.large, .accessibility3]
        )
        func lines(size: DynamicTypeSize) throws {
            // Local wall-clock times, so the HH:mm:ss.SSS timestamps read the same in every time zone.
            let morning = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 5, hour: 9, minute: 41)))
            let levels: [LogLine.Level] = [.info, .debug, .notice, .error]
            let lines = (0 ..< 40).map { index in
                LogLine(
                    timestamp: morning.addingTimeInterval(Double(index) / 4), text: "Request \(index) finished",
                    source: .oslog, level: levels[index % levels.count]
                )
            }
            let sut = ConsoleLinesWell(lines: lines, isFollowing: .constant(true))
            let controller = UIHostingController(rootView: sut
                .frame(width: 316, alignment: .leading)
                // No height proposed, as the drawer's scroll view proposes none.
                .fixedSize(horizontal: false, vertical: true)
                .padding()
                .background(.background)
                .environment(\.dynamicTypeSize, size))
            // No safe area: the window's status bar inset would lay the view out shorter than it
            // measured, overlapping its rows.
            controller.safeAreaRegions = []
            let measured = controller.sizeThatFits(in: CGSize(width: 348, height: 8000))
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            let window = scene.map(UIWindow.init(windowScene:)) ?? UIWindow()
            window.frame = CGRect(origin: .zero, size: measured)
            window.rootViewController = controller
            window.overrideUserInterfaceStyle = .light
            window.isHidden = false
            controller.view.frame = window.bounds
            window.layoutIfNeeded()
            controller.view.layer.displayIfNeeded()
            let format = UIGraphicsImageRendererFormat()
            format.scale = 2

            let actual = UIGraphicsImageRenderer(size: measured, format: format).image { context in
                controller.view.layer.render(in: context.cgContext)
            }
            window.isHidden = true

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: size == .large ? "large" : "accessibility3")
        }
    }
#endif
