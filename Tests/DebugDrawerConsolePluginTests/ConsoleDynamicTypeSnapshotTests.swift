// iOS scales text with Dynamic Type, so the large-text snapshots run on the iOS simulator.
#if os(iOS) && !targetEnvironment(macCatalyst)
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
            // window that is never shown and its layer rendered, at a fixed size and scale.
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

        @Test("Lines already shown restyle when the text size changes")
        func shownLinesRestyleOnATextSizeChange() throws {
            let lines = [LogLine(timestamp: Date(timeIntervalSince1970: 0), text: "App launched", source: .stdout, level: .info)]
            func console(_ size: DynamicTypeSize) -> AnyView {
                AnyView(ConsoleTextView(lines: lines, isFollowing: .constant(false))
                    .frame(width: 320, height: 120)
                    .environment(\.dynamicTypeSize, size))
            }
            func textView(in view: UIView) -> UITextView? {
                view as? UITextView ?? view.subviews.lazy.compactMap(textView(in:)).first
            }
            func shownFontSize(_ controller: UIHostingController<AnyView>) throws -> CGFloat {
                controller.view.layoutIfNeeded()
                let storage = try #require(textView(in: controller.view)?.textStorage)
                // The last character is the line's text, after the timestamp.
                let font = try #require(storage.attribute(.font, at: storage.length - 1, effectiveRange: nil) as? UIFont)
                return font.pointSize
            }
            let controller = UIHostingController(rootView: console(.large))
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 120))
            window.rootViewController = controller
            window.isHidden = false
            let before = try shownFontSize(controller)
            let expectedBefore: CGFloat = 13
            let expected = ConsoleFonts(dynamicTypeSize: .accessibility3).code.pointSize

            controller.rootView = console(.accessibility3)
            let actual = try shownFontSize(controller)
            window.isHidden = true

            #expect(before == expectedBefore)
            #expect(actual == expected)
        }

        @Test("The console's font is the drawer's code type, the footnote's 13 pt monospaced, at the default text size")
        func fontAtTheDefaultSize() {
            let expected: CGFloat = 13

            let actual = ConsoleFonts(dynamicTypeSize: .large).code

            #expect(actual.pointSize == expected)
            #expect(actual.fontDescriptor.symbolicTraits.contains(.traitMonoSpace))
        }

        @Test("The console's font grows at an accessibility text size")
        func fontGrowsAtAccessibilitySizes() {
            let standard = ConsoleFonts(dynamicTypeSize: .large)

            let actual = ConsoleFonts(dynamicTypeSize: .accessibility3)

            #expect(actual.code.pointSize > standard.code.pointSize)
        }
    }
#endif
