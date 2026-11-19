// The text view is AppKit's on the Mac, where the view tests run.
#if os(macOS)
    import AppKit
    @testable import DebugDrawerConsolePlugin
    import SwiftUI
    import Testing

    // The view is hosted in a window that is never shown, so SwiftUI makes and updates the
    // NSTextView as it would in the drawer; the tests read the text it holds.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct ConsoleTextViewTests {
        @Test("A line shows its subsystem's last component and its category before its text; a stdout line shows neither")
        func rowShowsSubsystemAndCategory() throws {
            func textView(in view: NSView) -> NSTextView? {
                view as? NSTextView ?? view.subviews.lazy.compactMap(textView(in:)).first
            }
            let time = Date(timeIntervalSince1970: 1_800_000_000)
            let lines = [
                LogLine(timestamp: time, text: "Timed out", source: .oslog, level: .info, subsystem: "com.example.feed", category: "networking"),
                LogLine(timestamp: time, text: "printed", source: .stdout, level: .info)
            ]
            let host = NSHostingView(rootView: ConsoleTextView(lines: lines, isFollowing: .constant(false)).frame(width: 316, height: 120))
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 316, height: 120), styleMask: .borderless, backing: .buffered, defer: true)
            window.contentView = host
            host.layoutSubtreeIfNeeded()

            let actual = try #require(textView(in: host)).string.split(separator: "\n").map { $0.split(separator: " ", maxSplits: 1)[1] }

            #expect(actual == ["feed/networking Timed out", "printed"])
        }

        @Test("A line from the sink shows its metadata as key=value fields after its text, in the tertiary color")
        func rowShowsMetadata() throws {
            func textView(in view: NSView) -> NSTextView? {
                view as? NSTextView ?? view.subviews.lazy.compactMap(textView(in:)).first
            }
            let time = Date(timeIntervalSince1970: 1_800_000_000)
            let lines = [
                LogLine(
                    timestamp: time, text: "Payment declined", source: .sink, level: .info, subsystem: "com.example.shop",
                    metadata: ["user": "7", "order": "1042"]
                )
            ]
            let host = NSHostingView(rootView: ConsoleTextView(lines: lines, isFollowing: .constant(false)).frame(width: 316, height: 120))
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 316, height: 120), styleMask: .borderless, backing: .buffered, defer: true)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            let storage = try #require(textView(in: host)?.textStorage)

            let actual = storage.string.split(separator: " ", maxSplits: 1)[1]
            let color = storage.attribute(.foregroundColor, at: storage.length - 1, effectiveRange: nil) as? NSColor

            #expect(actual == "shop Payment declined order=1042 user=7")
            #expect(color == NSColor.tertiaryLabelColor)
        }

        @Test("After a filter drops lines and others arrive, the text shows exactly the new list")
        func filterChangeRedraws() throws {
            func textView(in view: NSView) -> NSTextView? {
                view as? NSTextView ?? view.subviews.lazy.compactMap(textView(in:)).first
            }
            let lines = (0 ..< 4).map {
                LogLine(timestamp: Date(timeIntervalSince1970: Double($0)), text: "line \($0)", source: .stdout, level: .info)
            }
            let host = NSHostingView(
                rootView: ConsoleTextView(lines: Array(lines[..<3]), isFollowing: .constant(false)).frame(width: 316, height: 120)
            )
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 316, height: 120), styleMask: .borderless, backing: .buffered, defer: true)
            window.contentView = host
            host.layoutSubtreeIfNeeded()

            host.rootView = ConsoleTextView(lines: [lines[0], lines[2], lines[3]], isFollowing: .constant(false)).frame(width: 316, height: 120)
            host.layoutSubtreeIfNeeded()
            let afterFilter = try #require(textView(in: host)).string
            host.rootView = ConsoleTextView(lines: [lines[2], lines[3]], isFollowing: .constant(false)).frame(width: 316, height: 120)
            host.layoutSubtreeIfNeeded()
            let afterTrim = try #require(textView(in: host)).string

            #expect(afterFilter.split(separator: "\n").map { $0.split(separator: " ", maxSplits: 1)[1] } == ["line 0", "line 2", "line 3"])
            #expect(afterTrim.split(separator: "\n").map { $0.split(separator: " ", maxSplits: 1)[1] } == ["line 2", "line 3"])
        }

        @Test("Past the store's 2,000-line capacity, each batch still reaches the text: the newest line shows and the oldest are gone")
        func pastCapacityKeepsUpdating() async throws {
            func textView(in view: NSView) -> NSTextView? {
                view as? NSTextView ?? view.subviews.lazy.compactMap(textView(in:)).first
            }
            let store = ConsoleLogStore(muteStorage: FakeConsoleMuteStorage())
            let host = NSHostingView(rootView: ConsoleTextView(lines: [], isFollowing: .constant(false)).frame(width: 316, height: 120))
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 316, height: 120), styleMask: .borderless, backing: .buffered, defer: true)
            window.contentView = host
            var shown: [[Substring]] = []

            // Five batches of 500: the fifth arrives at capacity, so the store drops as many as
            // it adds and its count stays 2,000.
            for batch in 0 ..< 5 {
                let texts = (0 ..< 500).map { "line \(batch * 500 + $0)" }
                for text in texts {
                    store.ingest(LogLine(timestamp: Date(timeIntervalSince1970: 1_800_000_000), text: text, source: .stdout, level: .info))
                }
                for await _ in store.$lines.first(where: { $0.last?.text == texts.last }).values {}
                host.rootView = ConsoleTextView(lines: store.shownLines, isFollowing: .constant(false)).frame(width: 316, height: 120)
                host.layoutSubtreeIfNeeded()
                shown.append(try #require(textView(in: host)).string.split(separator: "\n").map { $0.split(separator: " ", maxSplits: 1)[1] })
            }
            let expectedAtCapacity = (0 ..< 2000).map { "line \($0)"[...] }
            let expected = (500 ..< 2500).map { "line \($0)"[...] }

            #expect(shown[3] == expectedAtCapacity)
            #expect(shown[4] == expected)
        }

        @Test("Switching the level from Errors to All, then searching, draws exactly the lines the store lists")
        func levelAndSearchChangesDrawTheFilteredLines() async throws {
            func textView(in view: NSView) -> NSTextView? {
                view as? NSTextView ?? view.subviews.lazy.compactMap(textView(in:)).first
            }
            // Each row's text: after its time, and after the error glyph's attachment character
            // on an error line.
            func texts(in string: String) -> [String] {
                string.split(separator: "\n").map { row in
                    let text = row.split(separator: " ", maxSplits: 1)[1]
                    return String(text.hasPrefix("\u{FFFC} ") ? text.dropFirst(2) : text)
                }
            }
            let store = ConsoleLogStore(muteStorage: FakeConsoleMuteStorage())
            let logged: [(String, LogLine.Level)] = [
                ("feed loaded", .info), ("feed failed", .error), ("cart shown", .debug), ("cart failed", .error), ("feed retried", .notice)
            ]
            for (text, level) in logged {
                store.ingest(LogLine(timestamp: Date(timeIntervalSince1970: 1_800_000_000), text: text, source: .oslog, level: level))
            }
            for await _ in store.$lines.first(where: { $0.count == logged.count }).values {}
            store.filterLevel = .error
            let host = NSHostingView(
                rootView: ConsoleTextView(lines: store.shownLines, isFollowing: .constant(false)).frame(width: 316, height: 120)
            )
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 316, height: 120), styleMask: .borderless, backing: .buffered, defer: true)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            let errors = try #require(textView(in: host)).string

            store.filterLevel = .debug
            host.rootView = ConsoleTextView(lines: store.shownLines, isFollowing: .constant(false)).frame(width: 316, height: 120)
            host.layoutSubtreeIfNeeded()
            let all = try #require(textView(in: host)).string
            store.searchText = "feed"
            host.rootView = ConsoleTextView(lines: store.shownLines, isFollowing: .constant(false)).frame(width: 316, height: 120)
            host.layoutSubtreeIfNeeded()
            let searched = try #require(textView(in: host)).string

            #expect(texts(in: errors) == ["feed failed", "cart failed"])
            #expect(texts(in: all) == logged.map(\.0))
            #expect(texts(in: searched) == ["feed loaded", "feed failed", "feed retried"])
        }

        // The Mac doesn't scale text, so large text is played by what it does to the well: lines
        // wrapped onto several rows each in a narrow well, which then grows taller, as the scaled
        // cap makes it on iOS.
        @Test("While following, wrapped lines in a well that grows after its first layout still end on the newest line, and the lines keep following")
        func followsThroughWrappingAndGrowth() async throws {
            func textView(in view: NSView) -> NSTextView? {
                view as? NSTextView ?? view.subviews.lazy.compactMap(textView(in:)).first
            }
            /// The text of the line drawn at the visible area's bottom edge.
            func bottomLine(of textView: NSTextView) -> String {
                let visible = textView.visibleRect
                let index = textView.characterIndexForInsertion(at: NSPoint(x: 1, y: visible.maxY - 1))
                let text = textView.string as NSString
                return text.substring(with: text.lineRange(for: NSRange(location: min(index, text.length - 1), length: 0)))
            }
            final class Following {
                var value = true
            }
            let following = Following()
            let isFollowing = Binding(get: { following.value }, set: { following.value = $0 })
            let lines = (0 ..< 40).map { index in
                LogLine(
                    timestamp: Date(timeIntervalSince1970: 1_800_000_000 + Double(index)), text: "Request \(index) finished",
                    source: .stdout, level: .info
                )
            }
            let host = NSHostingView(rootView: ConsoleTextView(lines: lines, isFollowing: isFollowing).frame(width: 120))
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 120, height: 120), styleMask: .borderless, backing: .buffered, defer: true)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            // The text view scrolls to its end in a block it queues on the main queue after each
            // update; this waits for the blocks queued before it, without a delay.
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
            let text = try #require(textView(in: host))
            let firstBottom = bottomLine(of: text)
            let firstHeight = text.visibleRect.height
            let rowHeight = NSLayoutManager().defaultLineHeight(for: ConsoleTextView.codeFont)

            window.setContentSize(CGSize(width: 120, height: 282))
            host.layoutSubtreeIfNeeded()
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
            let grownBottom = bottomLine(of: text)
            let gap = text.frame.height - text.visibleRect.maxY
            let grownHeight = text.visibleRect.height

            // Each line takes more than one row, as at a large text size.
            #expect(text.frame.height / CGFloat(lines.count) > 1.5 * rowHeight)
            #expect(firstHeight == 120)
            #expect(grownHeight == 282)
            #expect(firstBottom.hasSuffix("Request 39 finished"))
            #expect(grownBottom.hasSuffix("Request 39 finished"))
            #expect(abs(gap) < 1)
            #expect(following.value)
        }

        @Test("A line's context menu offers Mute Subsystem, Mute Category and Show Since This Line, and runs the one picked")
        func contextMenu() throws {
            func textView(in view: NSView) -> NSTextView? {
                view as? NSTextView ?? view.subviews.lazy.compactMap(textView(in:)).first
            }
            final class Performed {
                var actions: [ConsoleLineAction] = []
            }
            let performed = Performed()
            let time = Date(timeIntervalSince1970: 1_800_000_000)
            let lines = [
                LogLine(timestamp: time, text: "printed", source: .stdout, level: .info),
                LogLine(
                    timestamp: time.addingTimeInterval(1), text: "Timed out", source: .oslog, level: .info,
                    subsystem: "com.example.feed", category: "net"
                )
            ]
            let sut = ConsoleTextView(lines: lines, isFollowing: .constant(false)) { performed.actions.append($0) }
            let host = NSHostingView(rootView: sut.frame(width: 316, height: 120))
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 316, height: 120), styleMask: .borderless, backing: .buffered, defer: true)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            let text = try #require(textView(in: host))
            let event = try #require(NSEvent.mouseEvent(
                with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
            ))
            let secondLine = (text.string as NSString).range(of: "Timed out").location
            let expectedTitles = ["Mute Subsystem “com.example.feed”", "Mute Category “net”", "Show Since This Line"]

            let menu = try #require(text.delegate?.textView?(text, menu: NSMenu(), for: event, at: secondLine))
            let titles = menu.items.prefix(3).map(\.title)
            let mute = try #require(menu.items.first)
            _ = (mute.target as? NSObject)?.perform(mute.action, with: mute)

            #expect(titles == expectedTitles)
            #expect(menu.items[3].isSeparatorItem)
            #expect(performed.actions == [.mute(.subsystem("com.example.feed"))])
        }
    }
#endif
