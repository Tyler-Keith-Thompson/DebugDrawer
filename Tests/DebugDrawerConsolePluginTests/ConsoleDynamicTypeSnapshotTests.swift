// iOS scales text with Dynamic Type, so the large-text snapshots run on the iOS simulator.
#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit
    @testable import DebugDrawerConsolePlugin

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct ConsoleDynamicTypeSnapshotTests {
        @Test("The console's lines grow with a large accessibility text size and stay readable")
        func lines() throws {
            // Local wall-clock times, so the HH:mm:ss.SSS timestamps read the same in every time zone.
            let morning = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 5, hour: 9, minute: 41)))
            let lines = [
                LogLine(timestamp: morning, text: "App launched", source: .stdout, level: .info),
                LogLine(timestamp: morning.addingTimeInterval(0.25), text: "Fetching feed", source: .oslog, level: .debug),
                LogLine(timestamp: morning.addingTimeInterval(1.5), text: "Feed is stale; serving cache", source: .oslog, level: .notice),
                LogLine(timestamp: morning.addingTimeInterval(2), text: "Decoding failed: missing key 'id'", source: .stderr, level: .error)
            ]
            let sut = ConsoleTextView(lines: lines, isFollowing: .constant(false))
                .frame(width: 320, height: 240)
                .padding()
                .background(Color(uiColor: .systemBackground))
                .environment(\.dynamicTypeSize, .accessibility3)
            // ImageRenderer draws a UIViewRepresentable as a placeholder, so the view is hosted in a
            // window that is never shown and drawn with drawHierarchy, at a fixed size and scale.
            let controller = UIHostingController(rootView: sut)
            let size = CGSize(width: 352, height: 272)
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            let window = scene.map(UIWindow.init(windowScene:)) ?? UIWindow()
            window.frame = CGRect(origin: .zero, size: size)
            window.rootViewController = controller
            window.overrideUserInterfaceStyle = .light
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

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "accessibility3")
        }

        @Test("The console's fonts are 10, 9 and 8 pt at the default text size")
        func fontsAtTheDefaultSize() {
            let expected: [CGFloat] = [10, 9, 8]

            let fonts = ConsoleFonts(dynamicTypeSize: .large)
            let actual = [fonts.text.pointSize, fonts.small.pointSize, fonts.badge.pointSize]

            #expect(actual == expected)
        }

        @Test("Every console font grows at an accessibility text size")
        func fontsGrowAtAccessibilitySizes() {
            let standard = ConsoleFonts(dynamicTypeSize: .large)

            let actual = ConsoleFonts(dynamicTypeSize: .accessibility3)

            #expect(actual.text.pointSize > standard.text.pointSize)
            #expect(actual.small.pointSize > standard.small.pointSize)
            #expect(actual.badge.pointSize > standard.badge.pointSize)
        }
    }
#endif
