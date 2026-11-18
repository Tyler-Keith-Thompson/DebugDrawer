// iOS scales text with Dynamic Type, so the large-text snapshots run on the iOS simulator.
#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit
    @testable import DebugDrawerConsolePlugin

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct ConsoleMetadataDynamicTypeSnapshotTests {
        @Test(
            "A line's metadata follows its text at the default size, and starts a line of its own under it at an accessibility size",
            arguments: [DynamicTypeSize.large, .accessibility3]
        )
        func metadata(size: DynamicTypeSize) throws {
            // Local wall-clock times, so the HH:mm:ss.SSS timestamps read the same in every time zone.
            let morning = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 5, hour: 9, minute: 41)))
            let lines = [
                LogLine(
                    timestamp: morning, text: "Payment declined", source: .sink, level: .error,
                    subsystem: "com.example.shop", category: "checkout", metadata: ["order": "1042", "card": "visa", "user": "7"]
                )
            ]
            let sut = ConsoleTextView(lines: lines, isFollowing: .constant(false))
                .frame(width: 320, height: 300)
                .padding()
                .background(Color(uiColor: .systemBackground))
                .environment(\.dynamicTypeSize, size)
            // ImageRenderer draws a UIViewRepresentable as a placeholder, so the view is hosted in a
            // window that is never shown and its layer rendered, at a fixed size and scale.
            let controller = UIHostingController(rootView: sut)
            let imageSize = CGSize(width: 352, height: 332)
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            let window = scene.map(UIWindow.init(windowScene:)) ?? UIWindow()
            window.frame = CGRect(origin: .zero, size: imageSize)
            window.rootViewController = controller
            window.overrideUserInterfaceStyle = .light
            window.isHidden = false
            controller.view.frame = window.bounds
            window.layoutIfNeeded()
            controller.view.layer.displayIfNeeded()
            let format = UIGraphicsImageRendererFormat()
            format.scale = 2
            let actual = UIGraphicsImageRenderer(size: imageSize, format: format).image { context in
                controller.view.layer.render(in: context.cgContext)
            }
            window.isHidden = true

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: size == .large ? "large" : "accessibility3")
        }
    }
#endif
