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
