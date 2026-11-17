// ViewInspector is linked on Apple platforms only, and the views are tested on the Mac.
#if os(macOS)
    @testable import DebugDrawer
    @testable import DebugDrawerConsolePlugin
    import Foundation
    import SwiftUI
    import Testing
    import ViewInspector

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct ConsoleFilterViewTests {
        @Test("An invalid pattern shows its problem under the search field")
        func invalidPatternShowsAnError() throws {
            let sut = ConsoleSearchField(text: .constant("fe+d("), isRegularExpression: .constant(true), issue: ConsoleSearch.InvalidPattern())
            let expected = "Not a valid regular expression. The list keeps the last valid search."

            let view = try sut.inspect()

            #expect(throws: Never.self) { try view.find(text: "Invalid pattern") }
            #expect(throws: Never.self) { try view.find(text: expected) }
        }

        @Test("A valid search shows no problem")
        func validSearchShowsNoError() throws {
            let sut = ConsoleSearchField(text: .constant("feed"), isRegularExpression: .constant(true), issue: nil)

            let view = try sut.inspect()

            #expect((try? view.find(text: "Invalid pattern")) == nil)
        }

        @Test("The .* button turns regular-expression search on, and says whether it is")
        func regularExpressionToggle() throws {
            final class Toggle {
                var isOn = false
            }
            let toggle = Toggle()
            let sut = ConsoleSearchField(
                text: .constant(""), isRegularExpression: Binding(get: { toggle.isOn }, set: { toggle.isOn = $0 }), issue: nil
            )

            let button = try sut.inspect().find(button: ".*")
            let value = try button.accessibilityValue().string()
            try button.tap()

            #expect(value == "Off")
            #expect(toggle.isOn)
        }

        @Test("While mutes hide lines, the hint counts them, with Show and an Unmute menu of each mute")
        func mutedHint() throws {
            var toggles = 0
            var unmuted: [ConsoleMute] = []
            var unmutedAll = 0
            let mutes: [ConsoleMute] = [.subsystem("com.example.feed"), .category("ui", subsystem: "com.example.cart")]
            let sut = ConsoleMutedHint(
                count: 12, mutes: mutes, isShowing: false,
                toggle: { toggles += 1 }, unmute: { unmuted.append($0) }, unmuteAll: { unmutedAll += 1 }
            )

            let view = try sut.inspect()
            try view.find(button: "Show").tap()
            try view.find(button: "com.example.cart: ui").tap()
            try view.find(button: "Unmute All").tap()

            #expect(throws: Never.self) { try view.find(text: "12 muted") }
            #expect(toggles == 1)
            #expect(unmuted == [.category("ui", subsystem: "com.example.cart")])
            #expect(unmutedAll == 1)
        }

        @Test("While muted lines show, the hint says so and offers Hide")
        func mutedHintShowing() throws {
            let sut = ConsoleMutedHint(
                count: 3, mutes: [.subsystem("com.example.feed")], isShowing: true, toggle: {}, unmute: { _ in }, unmuteAll: {}
            )

            let view = try sut.inspect()

            #expect(throws: Never.self) { try view.find(text: "3 muted, shown") }
            #expect(throws: Never.self) { try view.find(button: "Hide") }
        }

        @Test("With no muted lines among those shown, the hint shows nothing")
        func mutedHintHidden() throws {
            let sut = ConsoleMutedHint(
                count: 0, mutes: [.subsystem("com.example.feed")], isShowing: false, toggle: {}, unmute: { _ in }, unmuteAll: {}
            )

            let view = try sut.inspect()

            #expect((try? view.find(button: "Show")) == nil)
        }

        @Test("A time range names itself under the log with Show All; All shows nothing")
        func timeRangeHint() throws {
            var showAll = 0
            let sut = ConsoleTimeRangeHint(timeRange: .last(minutes: 5)) { showAll += 1 }
            let all = ConsoleTimeRangeHint(timeRange: .all) {}

            let view = try sut.inspect()
            try view.find(button: "Show All").tap()

            #expect(throws: Never.self) { try view.find(text: "Last 5 Minutes") }
            #expect(showAll == 1)
            #expect((try? all.inspect().find(button: "Show All")) == nil)
        }

        @Test("More offers Copy All, the time range presets, and muting each subsystem and category shown")
        func moreMenu() throws {
            final class Range {
                var value = ConsoleTimeRange.all
            }
            let range = Range()
            var muted: [ConsoleMute] = []
            var copies = 0
            let sut = ConsoleMoreMenu(
                timeRange: Binding(get: { range.value }, set: { range.value = $0 }),
                mutes: [.subsystem("com.example.auth")],
                muteChoices: [.subsystem("com.example.feed"), .category("net", subsystem: "com.example.feed")],
                mute: { muted.append($0) },
                unmute: { _ in },
                copyAll: { copies += 1 }
            )

            let view = try sut.inspect()
            try view.find(button: "Copy All").tap()
            let picker = try view.find(ViewType.Picker.self) { try $0.accessibilityLabel().string() == "Time Range" }
            try picker.select(value: ConsoleTimeRange.last(minutes: 5))
            try view.find(button: "com.example.feed").tap()
            try view.find(button: "com.example.feed: net").tap()

            #expect(copies == 1)
            #expect(range.value == .last(minutes: 5))
            #expect(muted == [.subsystem("com.example.feed"), .category("net", subsystem: "com.example.feed")])
            #expect(throws: Never.self) { try view.find(text: "Last 15 Minutes") }
            #expect(throws: Never.self) { try view.find(button: "com.example.auth") }
        }
    }
#endif
