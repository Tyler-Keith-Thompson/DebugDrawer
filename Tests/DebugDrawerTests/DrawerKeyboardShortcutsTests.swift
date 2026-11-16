// Views render on the Mac; ViewInspector is linked on Apple platforms only.
#if os(macOS)
    import AppKit
    @testable import DebugDrawer
    import SwiftUI
    import Testing
    import ViewInspector

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct DrawerKeyboardShortcutsTests {
        @Test("Cmd-K searches, Cmd-Option-Down and Up move between plugins, and Escape closes")
        func keys() {
            let expected: [KeyboardShortcut] = [
                KeyboardShortcut("k", modifiers: .command),
                KeyboardShortcut(.downArrow, modifiers: [.command, .option]),
                KeyboardShortcut(.upArrow, modifiers: [.command, .option]),
                KeyboardShortcut(.escape, modifiers: [])
            ]

            let actual = DrawerKeyboardShortcuts.Command.allCases.map(\.shortcut)

            #expect(actual == expected)
        }

        @Test("Cmd-K pressed in the drawer's window focuses the search field")
        func searchInAWindow() throws {
            var searched = 0
            let sut = DrawerKeyboardShortcuts(closesOnEscape: true, search: { searched += 1 }, nextPlugin: {}, previousPlugin: {}, close: {})
            let host = NSHostingView(rootView: sut.frame(width: 100, height: 100))
            host.frame = NSRect(x: 0, y: 0, width: 100, height: 100)
            let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            let key = try #require(NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.command],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                characters: "k",
                charactersIgnoringModifiers: "k",
                isARepeat: false,
                keyCode: 40
            ))

            let handled = window.performKeyEquivalent(with: key)

            #expect(handled)
            #expect(searched == 1)
        }

        @Test("Cmd-Option-Up pressed in the drawer's window moves to the previous plugin")
        func previousPluginInAWindow() throws {
            var moved = 0
            let up = "\u{F700}" // NSUpArrowFunctionKey
            let sut = DrawerKeyboardShortcuts(closesOnEscape: true, search: {}, nextPlugin: {}, previousPlugin: { moved += 1 }, close: {})
            let host = NSHostingView(rootView: sut.frame(width: 100, height: 100))
            host.frame = NSRect(x: 0, y: 0, width: 100, height: 100)
            let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            let key = try #require(NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.command, .option, .numericPad, .function],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                characters: up,
                charactersIgnoringModifiers: up,
                isARepeat: false,
                keyCode: 126
            ))

            let handled = window.performKeyEquivalent(with: key)

            #expect(handled)
            #expect(moved == 1)
        }

        @Test("Escape pressed while the search field holds text leaves the drawer open")
        func escapeWithSearchTextInAWindow() throws {
            var closed = 0
            let sut = DrawerKeyboardShortcuts(closesOnEscape: false, search: {}, nextPlugin: {}, previousPlugin: {}, close: { closed += 1 })
            let host = NSHostingView(rootView: sut.frame(width: 100, height: 100))
            host.frame = NSRect(x: 0, y: 0, width: 100, height: 100)
            let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            let key = try #require(NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                characters: "\u{1B}",
                charactersIgnoringModifiers: "\u{1B}",
                isARepeat: false,
                keyCode: 53
            ))

            let handled = window.performKeyEquivalent(with: key)

            #expect(!handled)
            #expect(closed == 0)
        }

        @Test("The shortcuts' buttons are hidden, so they draw nothing and VoiceOver skips them")
        func hidden() throws {
            let sut = DrawerKeyboardShortcuts(closesOnEscape: true, search: {}, nextPlugin: {}, previousPlugin: {}, close: {})

            let actual = try sut.inspect().findAll(ViewType.Button.self).map { $0.isHidden() }

            #expect(actual == [true, true, true, true])
        }

        @Test("While the search field holds text, Escape is left to clear it and doesn't close the drawer")
        func escapeClearsSearchFirst() throws {
            let sut = DrawerKeyboardShortcuts(closesOnEscape: false, search: {}, nextPlugin: {}, previousPlugin: {}, close: {})
            let expected = ["Search Plugins", "Next Plugin", "Previous Plugin"]

            let actual = try sut.inspect().findAll(ViewType.Button.self).map { try $0.labelView().text().string() }

            #expect(actual == expected)
        }

        @Test("Escape pressed in the drawer's window closes it")
        func escapeInAWindowCloses() throws {
            var closed = 0
            let sut = DrawerKeyboardShortcuts(closesOnEscape: true, search: {}, nextPlugin: {}, previousPlugin: {}, close: { closed += 1 })
            let host = NSHostingView(rootView: sut.frame(width: 100, height: 100))
            host.frame = NSRect(x: 0, y: 0, width: 100, height: 100)
            let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            let escape = try #require(NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                characters: "\u{1B}",
                charactersIgnoringModifiers: "\u{1B}",
                isARepeat: false,
                keyCode: 53
            ))

            let handled = window.performKeyEquivalent(with: escape)

            #expect(handled)
            #expect(closed == 1)
        }

        @Test("Cmd-Option-Down pressed in the drawer's window moves to the next plugin")
        func nextPluginInAWindow() throws {
            var moved = 0
            let sut = DrawerKeyboardShortcuts(closesOnEscape: true, search: {}, nextPlugin: { moved += 1 }, previousPlugin: {}, close: {})
            let host = NSHostingView(rootView: sut.frame(width: 100, height: 100))
            host.frame = NSRect(x: 0, y: 0, width: 100, height: 100)
            let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            let down = "\u{F701}" // NSDownArrowFunctionKey
            let key = try #require(NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.command, .option, .numericPad, .function],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                characters: down,
                charactersIgnoringModifiers: down,
                isARepeat: false,
                keyCode: 125
            ))

            let handled = window.performKeyEquivalent(with: key)

            #expect(handled)
            #expect(moved == 1)
        }

        @Test("Moving from a plugin steps through the list's order")
        func stepsThroughTheOrder() {
            let order = ["a", "b", "c"]

            let next = DrawerKeyboardShortcuts.plugin(by: 1, from: "a", in: order)
            let previous = DrawerKeyboardShortcuts.plugin(by: -1, from: "c", in: order)

            #expect(next == "b")
            #expect(previous == "b")
        }

        @Test("Moving stops at the first and last plugins rather than wrapping")
        func stopsAtTheEnds() {
            let order = ["a", "b", "c"]

            let pastLast = DrawerKeyboardShortcuts.plugin(by: 1, from: "c", in: order)
            let beforeFirst = DrawerKeyboardShortcuts.plugin(by: -1, from: "a", in: order)

            #expect(pastLast == "c")
            #expect(beforeFirst == "a")
        }

        @Test("With no plugin at the top, or one no longer listed, moving counts from the first")
        func unknownCountsAsFirst() {
            let order = ["a", "b", "c"]

            let fromNothing = DrawerKeyboardShortcuts.plugin(by: 1, from: nil, in: order)
            let fromGone = DrawerKeyboardShortcuts.plugin(by: 1, from: "removed", in: order)

            #expect(fromNothing == "b")
            #expect(fromGone == "b")
        }

        @Test("A list of one plugin stays on it, and an empty list has nowhere to move")
        func shortLists() {
            let one = DrawerKeyboardShortcuts.plugin(by: 1, from: "a", in: ["a"])
            let none = DrawerKeyboardShortcuts.plugin(by: 1, from: nil, in: [])

            #expect(one == "a")
            #expect(none == nil)
        }
    }
#endif
