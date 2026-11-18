// iOS scales text with Dynamic Type, so the large-text snapshots run on the iOS simulator.
#if os(iOS) && !targetEnvironment(macCatalyst)
    import DebugDrawer
    @testable import DebugDrawerConsolePlugin
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct ConsoleFilterDynamicTypeSnapshotTests {
        @Test(
            "The filters at the default and an accessibility text size: a pattern's error, the toolbar, lines with subsystem and category, the hints",
            arguments: [DynamicTypeSize.large, .accessibility3]
        )
        func filters(size: DynamicTypeSize) throws {
            // Local wall-clock times, so the HH:mm:ss.SSS timestamps read the same in every time zone.
            let morning = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 5, hour: 9, minute: 41)))
            let lines = [
                LogLine(timestamp: morning, text: "App launched", source: .stdout, level: .info),
                LogLine(
                    timestamp: morning.addingTimeInterval(0.25), text: "GET /feed 200", source: .oslog, level: .debug,
                    subsystem: "com.example.feed", category: "networking"
                ),
                LogLine(
                    timestamp: morning.addingTimeInterval(2), text: "Decoding failed: missing key 'id'", source: .oslog, level: .error,
                    subsystem: "com.example.feed", category: "decoding"
                )
            ]
            let sut = VStack(alignment: .leading, spacing: 0) {
                ConsoleSearchField(text: .constant("feed("), isRegularExpression: .constant(true), issue: ConsoleSearch.InvalidPattern()) {
                    ConsoleMoreMenu(
                        timeRange: .constant(.last(minutes: 5)), mutes: [], muteChoices: [], mute: { _ in }, unmute: { _ in }, copyAll: {}
                    )
                }
                ConsoleToolbarView(
                    isFollowing: .constant(true), filterLevel: .constant(.debug),
                    clear: {}
                )
                DebugDrawerCodeBlock {
                    ConsoleTextView(lines: lines, isFollowing: .constant(false))
                        .frame(height: size.isAccessibilitySize ? 260 : 110)
                }
                ConsoleTimeRangeHint(timeRange: .last(minutes: 5)) {}
                ConsoleMutedHint(count: 12, mutes: [.subsystem("com.example.cart")], isShowing: false, toggle: {}, unmute: { _ in }, unmuteAll: {})
            }
            .frame(width: 316, alignment: .leading)
            .padding()
            .background(Color(uiColor: .systemBackground))
            .environment(\.dynamicTypeSize, size)
            // ImageRenderer draws UIKit-backed controls (the text field, the segmented picker, the
            // text view) as placeholders, so the view is hosted in a window that is never shown and
            // its layer is rendered, at a fixed width and scale.
            let controller = UIHostingController(rootView: sut)
            // No safe area: the window's status bar inset would lay the view out shorter than it
            // measured, overlapping its rows.
            controller.safeAreaRegions = []
            let fitted = controller.sizeThatFits(in: CGSize(width: 348, height: 3000))
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            let window = scene.map(UIWindow.init(windowScene:)) ?? UIWindow()
            window.frame = CGRect(origin: .zero, size: fitted)
            window.rootViewController = controller
            window.overrideUserInterfaceStyle = .light
            window.isHidden = false
            controller.view.frame = window.bounds
            window.layoutIfNeeded()
            controller.view.layer.displayIfNeeded()
            let format = UIGraphicsImageRendererFormat()
            format.scale = 2
            let actual = UIGraphicsImageRenderer(size: fitted, format: format).image { context in
                controller.view.layer.render(in: context.cgContext)
            }
            window.isHidden = true

            // DD-182: a hosted text field's caret and edge render a few pixels differently from
            // run to run, so 99% of the pixels must match rather than all of them.
            assertSnapshot(of: actual, as: .image(precision: 0.99, perceptualPrecision: 0.98), named: "\(size)")
        }
    }
#endif
