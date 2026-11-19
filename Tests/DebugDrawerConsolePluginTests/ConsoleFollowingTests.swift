// The text view is UIKit's on iOS, where text scales with Dynamic Type. ViewHosting hosts a view in
// a window, which UIKit can't make in xctest's Mac Catalyst runs.
#if os(iOS) && !targetEnvironment(macCatalyst)
    import Combine
    @testable import DebugDrawerConsolePlugin
    import SwiftUI
    import Testing
    import UIKit
    import ViewInspector

    // ViewInspector's hook for views with their own state, approach #2 of its guide; the Console
    // module keeps none of its own, so the probe below carries this one.
    @MainActor
    final class Inspection<V>: InspectionEmissary {
        let notice = PassthroughSubject<UInt, Never>()
        var callbacks: [UInt: (V) -> Void] = [:]

        func visit(_ view: V, _ line: UInt) {
            if let callback = callbacks.removeValue(forKey: line) {
                callback(view)
            }
        }
    }

    /// The toolbar and the lines' well over one `isFollowing`, as the plugin's view holds them, at
    /// the drawer's width with no height proposed.
    struct ConsoleFollowingProbe: View {
        let lines: [LogLine]
        let inspection = Inspection<Self>()
        @State var isFollowing = true

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                ConsoleToolbarView(isFollowing: $isFollowing, filterLevel: .constant(.debug), clear: {})
                ConsoleLinesWell(lines: lines, isFollowing: $isFollowing)
            }
            .frame(width: 316, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onReceive(inspection.notice) { inspection.visit(self, $0) }
        }
    }

    @MainActor
    // Serialized: ViewHosting shares one window, and a test finds its text view in it by type.
    @Suite(.serialized, .timeLimit(.minutes(1)))
    struct ConsoleFollowingTests {
        @Test("While following at accessibility3, the well's last line is the newest one, with nothing below it")
        func lastLineAtAccessibility3() throws {
            func textView(in view: UIView) -> ConsoleFollowingTextView? {
                view as? ConsoleFollowingTextView ?? view.subviews.lazy.compactMap(textView(in:)).first
            }
            /// The text of the line drawn at the well's bottom edge.
            func bottomLine(of textView: UITextView) -> String? {
                let bottom = CGPoint(x: 1, y: textView.contentOffset.y + textView.bounds.height - 1)
                guard let position = textView.closestPosition(to: bottom) else { return nil }
                let offset = textView.offset(from: textView.beginningOfDocument, to: position)
                let text = textView.text as NSString
                return text.substring(with: text.lineRange(for: NSRange(location: min(offset, text.length - 1), length: 0)))
            }
            let lines = (0 ..< 40).map { index in
                LogLine(
                    timestamp: Date(timeIntervalSince1970: 1_800_000_000 + Double(index)), text: "Request \(index) finished",
                    source: .oslog, level: .info
                )
            }
            let controller = UIHostingController(rootView: ConsoleLinesWell(lines: lines, isFollowing: .constant(true))
                .frame(width: 316, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .environment(\.dynamicTypeSize, .accessibility3))
            controller.safeAreaRegions = []
            let measured = controller.sizeThatFits(in: CGSize(width: 316, height: 8000))
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            let window = scene.map(UIWindow.init(windowScene:)) ?? UIWindow()
            window.frame = CGRect(origin: .zero, size: measured)
            window.rootViewController = controller
            window.isHidden = false
            controller.view.frame = window.bounds

            window.layoutIfNeeded()
            let well = try #require(textView(in: controller.view))
            let actual = bottomLine(of: well)
            let shownBottom = well.contentOffset.y + well.bounds.height
            let contentHeight = well.contentSize.height
            window.isHidden = true

            #expect(actual?.hasSuffix("Request 39 finished") == true)
            #expect(abs(contentHeight - shownBottom) < 1)
        }

        @Test("With no scroll by the person, the lines still follow after the first layout and after the text size grows to accessibility3")
        func followsThroughLayoutAndDynamicType() async throws {
            let lines = (0 ..< 40).map { index in
                LogLine(
                    timestamp: Date(timeIntervalSince1970: 1_800_000_000 + Double(index)), text: "Request \(index) finished",
                    source: .oslog, level: .info
                )
            }
            /// What the probe shows at one moment.
            struct Seen {
                let isFollowing: Bool
                let hasResume: Bool
                /// How far the text runs on below the well's bottom edge.
                let hiddenBelow: CGFloat
                let fontSize: CGFloat
                let wellHeight: CGFloat
            }
            func seen(in view: InspectableView<ViewType.View<ConsoleFollowingProbe>>) throws -> Seen {
                let textView = try view.find(ConsoleTextView.self).actualView().uiView()
                textView.window?.layoutIfNeeded()
                return Seen(
                    isFollowing: try view.actualView().isFollowing,
                    hasResume: (try? view.find(button: "Resume")) != nil,
                    hiddenBelow: textView.contentSize.height - (textView.contentOffset.y + textView.bounds.height),
                    fontSize: (textView.textStorage.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)?.pointSize ?? 0,
                    wellHeight: textView.bounds.height
                )
            }
            let sut = ConsoleFollowingProbe(lines: lines)
            var afterFirstLayout: Seen?
            var afterLargerText: Seen?

            try await ViewHosting.host(sut) {
                try await sut.inspection.inspect { view in
                    afterFirstLayout = try seen(in: view)
                    // The person's text size, as Settings sets it: a trait of the hosting controller.
                    let textView = try view.find(ConsoleTextView.self).actualView().uiView()
                    var responder: UIResponder? = textView
                    while let next = responder?.next, !(next is UIHostingController<ConsoleFollowingProbe>) { responder = next }
                    let controller = try #require(responder?.next as? UIViewController)
                    controller.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
                    textView.window?.layoutIfNeeded()
                }
                try await sut.inspection.inspect { view in
                    afterLargerText = try seen(in: view)
                }
            }

            let first = try #require(afterFirstLayout)
            let larger = try #require(afterLargerText)
            #expect(first.isFollowing)
            #expect(!first.hasResume)
            #expect(abs(first.hiddenBelow) < 1)
            #expect(larger.fontSize > first.fontSize)
            #expect(larger.wellHeight > first.wellHeight)
            #expect(larger.isFollowing)
            #expect(!larger.hasResume)
            #expect(abs(larger.hiddenBelow) < 1)
        }

        @Test("A drag up stops the lines following and shows Resume, and a layout after it leaves them where the person scrolled")
        func dragUpStopsFollowing() async throws {
            let lines = (0 ..< 40).map { index in
                LogLine(
                    timestamp: Date(timeIntervalSince1970: 1_800_000_000 + Double(index)), text: "Request \(index) finished",
                    source: .oslog, level: .info
                )
            }
            let sut = ConsoleFollowingProbe(lines: lines)
            var isFollowing: Bool?
            var hasResume: Bool?
            var offset: CGFloat?

            try await ViewHosting.host(sut) {
                try await sut.inspection.inspect { view in
                    let textView = try view.find(ConsoleTextView.self).actualView().uiView()
                    textView.window?.layoutIfNeeded()
                    // A drag as UIKit reports one to the scroll view's delegate: it begins, the
                    // content moves to the top, and it ends without decelerating.
                    let delegate = try #require(textView.delegate)
                    delegate.scrollViewWillBeginDragging?(textView)
                    textView.contentOffset = .zero
                    delegate.scrollViewDidEndDragging?(textView, willDecelerate: false)
                }
                try await sut.inspection.inspect { view in
                    let textView = try view.find(ConsoleTextView.self).actualView().uiView()
                    textView.setNeedsLayout()
                    textView.window?.layoutIfNeeded()
                    isFollowing = try view.actualView().isFollowing
                    hasResume = (try? view.find(button: "Resume")) != nil
                    offset = textView.contentOffset.y
                }
            }

            #expect(isFollowing == false)
            #expect(hasResume == true)
            #expect(offset == 0)
        }
    }
#endif
