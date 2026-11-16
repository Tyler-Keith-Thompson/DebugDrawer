// ViewInspector is linked on Apple platforms only, and the views are tested on the Mac.
#if os(macOS)
    @testable import DebugDrawer
    @testable import DebugDrawerHangDetectorPlugin
    import Foundation
    import SwiftUI
    import Testing
    import ViewInspector

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct HangsViewTests {
        @Test("With no hangs the plugin says when one will appear, and offers no buttons")
        func empty() throws {
            let sut = HangsView(
                events: [], threshold: .constant(.milliseconds(250)), expanded: .constant(nil), onOpen: { _ in }, onMarkAllSeen: {}, onClear: {}
            )
            let expected = "No hangs. Each time the main thread is stuck for longer than the threshold, the hang appears here with its stack."

            let actual = try sut.inspect().find(text: expected).string()

            #expect(actual == expected)
            #expect(throws: (any Error).self) { try sut.inspect().find(button: "Clear All") }
        }

        @Test("The threshold picker offers the fixed choices, shortest first")
        func thresholdChoices() throws {
            let sut = HangsView(
                events: [], threshold: .constant(.milliseconds(250)), expanded: .constant(nil), onOpen: { _ in }, onMarkAllSeen: {}, onClear: {}
            )
            let expected = ["100 ms", "250 ms", "500 ms", "1000 ms", "2000 ms"]

            let actual = try sut.inspect().find(ViewType.Picker.self).findAll(ViewType.Text.self).map { try $0.string() }.filter { $0 != "Threshold" }

            #expect(actual == expected)
        }

        @Test("A threshold install was given that isn't a fixed choice is offered among them")
        func customThreshold() throws {
            let sut = HangsView(
                events: [], threshold: .constant(.milliseconds(400)), expanded: .constant(nil), onOpen: { _ in }, onMarkAllSeen: {}, onClear: {}
            )
            let expected = ["100 ms", "250 ms", "400 ms", "500 ms", "1000 ms", "2000 ms"]

            let actual = try sut.inspect().find(ViewType.Picker.self).findAll(ViewType.Text.self).map { try $0.string() }.filter { $0 != "Threshold" }

            #expect(actual == expected)
        }

        @Test("Choosing a threshold sets it")
        func chooseThreshold() throws {
            var threshold = Duration.milliseconds(250)
            let sut = HangsView(
                events: [], threshold: Binding(get: { threshold }, set: { threshold = $0 }), expanded: .constant(nil),
                onOpen: { _ in }, onMarkAllSeen: {}, onClear: {}
            )

            try sut.inspect().find(ViewType.Picker.self).select(value: Duration.milliseconds(1000))

            #expect(threshold == .milliseconds(1000))
        }

        @Test("Tapping a hang opens it and reports it opened; tapping it again closes it")
        func toggle() throws {
            let event = HangEvent(
                id: UUID(), date: Date(timeIntervalSince1970: 1_763_290_000), duration: .milliseconds(612),
                frames: ["0 Example 0x1"], source: .detected, isSeen: false
            )
            var expanded: HangEvent.ID?
            var opened: [HangEvent.ID] = []
            let sut = HangsView(
                events: [event], threshold: .constant(.milliseconds(250)),
                expanded: Binding(get: { expanded }, set: { expanded = $0 }),
                onOpen: { opened.append($0) }, onMarkAllSeen: {}, onClear: {}
            )

            try sut.inspect().find(button: "612 ms").tap()

            #expect(expanded == event.id)
            #expect(opened == [event.id])

            try sut.inspect().find(button: "612 ms").tap()

            #expect(expanded == nil)
            #expect(opened == [event.id])
        }

        @Test("An open hang shows each frame of its stack, symbol and image, and a button that copies the hang")
        func expandedShowsFrames() throws {
            let event = HangEvent(
                id: UUID(), date: Date(timeIntervalSince1970: 1_763_290_000), duration: .milliseconds(612),
                frames: ["0 Example 0x1 block + 4", "1 Example 0x2 main + 8"], source: .detected, isSeen: true
            )
            let sut = HangsView(
                events: [event], threshold: .constant(.milliseconds(250)), expanded: .constant(event.id),
                onOpen: { _ in }, onMarkAllSeen: {}, onClear: {}
            )
            let expected = ["block", "main", "Example"]

            let actual = try [
                sut.inspect().find(text: "block").string(),
                sut.inspect().find(text: "main").string(),
                sut.inspect().find(text: "Example").string()
            ]

            #expect(actual == expected)
            #expect(try sut.inspect().find(button: "Copy Report").labelView().text().string() == "Copy Report")
        }

        @Test("An open hang with no stack says why")
        func expandedWithoutStack() throws {
            let event = HangEvent(
                id: UUID(), date: Date(timeIntervalSince1970: 1), duration: .milliseconds(260), frames: [], source: .detected, isSeen: true
            )
            let sut = HangsView(
                events: [event], threshold: .constant(.milliseconds(250)), expanded: .constant(event.id),
                onOpen: { _ in }, onMarkAllSeen: {}, onClear: {}
            )
            let expected = "No stack was captured: the main thread got going before the watcher looked."

            let actual = try sut.inspect().find(text: expected).string()

            #expect(actual == expected)
        }

        @Test("A closed hang shows no stack")
        func collapsedHidesFrames() throws {
            let event = HangEvent(
                id: UUID(), date: Date(timeIntervalSince1970: 1), duration: .milliseconds(612), frames: ["0 Example 0x1"],
                source: .detected, isSeen: true
            )
            let sut = HangsView(
                events: [event], threshold: .constant(.milliseconds(250)), expanded: .constant(nil),
                onOpen: { _ in }, onMarkAllSeen: {}, onClear: {}
            )

            #expect(throws: (any Error).self) { try sut.inspect().find(text: "0 Example 0x1") }
        }

        @Test("An unopened hang has an unread dot; an opened one hasn't")
        func newTag() throws {
            let unseen = HangEvent(
                id: UUID(), date: Date(timeIntervalSince1970: 2), duration: .milliseconds(300), frames: [], source: .detected, isSeen: false
            )
            let seen = HangEvent(
                id: UUID(), date: Date(timeIntervalSince1970: 1), duration: .milliseconds(400), frames: [], source: .detected, isSeen: true
            )
            let sut = HangsView(
                events: [unseen, seen], threshold: .constant(.milliseconds(250)), expanded: .constant(nil),
                onOpen: { _ in }, onMarkAllSeen: {}, onClear: {}
            )

            let actual = try sut.inspect().findAll(DebugDrawerUnreadDot.self)

            #expect(actual.count == 1)
            #expect(try actual.first?.accessibilityLabel().string() == "New hang")
        }

        @Test("VoiceOver reads the duration as how long the main thread hung")
        func durationLabel() throws {
            let event = HangEvent(
                id: UUID(), date: Date(timeIntervalSince1970: 1), duration: .milliseconds(612), frames: [], source: .detected, isSeen: true
            )
            let sut = HangsView(
                events: [event], threshold: .constant(.milliseconds(250)), expanded: .constant(nil),
                onOpen: { _ in }, onMarkAllSeen: {}, onClear: {}
            )

            let actual = try sut.inspect().find(button: "612 ms").accessibilityLabel().string()

            #expect(actual == "Hung for 612 ms")
        }

        @Test("Clear All and Mark All Seen call their actions")
        func buttons() throws {
            let event = HangEvent(
                id: UUID(), date: Date(timeIntervalSince1970: 1), duration: .milliseconds(300), frames: [], source: .detected, isSeen: false
            )
            var calls: [String] = []
            let sut = HangsView(
                events: [event], threshold: .constant(.milliseconds(250)), expanded: .constant(nil), onOpen: { _ in },
                onMarkAllSeen: { calls.append("seen") }, onClear: { calls.append("clear") }
            )

            try sut.inspect().find(button: "Mark All Seen").tap()
            try sut.inspect().find(button: "Clear All").tap()

            #expect(calls == ["seen", "clear"])
        }

        @Test("Mark All Seen is disabled once every hang is seen")
        func markAllSeenDisabled() throws {
            let event = HangEvent(
                id: UUID(), date: Date(timeIntervalSince1970: 1), duration: .milliseconds(300), frames: [], source: .detected, isSeen: true
            )
            let sut = HangsView(
                events: [event], threshold: .constant(.milliseconds(250)), expanded: .constant(nil),
                onOpen: { _ in }, onMarkAllSeen: {}, onClear: {}
            )

            let actual = try sut.inspect().find(button: "Mark All Seen").isDisabled()

            #expect(actual)
        }

        @Test("The summary reads the start in the view's locale and time zone, with the source")
        func facts() throws {
            let event = HangEvent(
                id: UUID(), date: Date(timeIntervalSince1970: 1_763_290_000), duration: .seconds(2), frames: [], source: .metricKit, isSeen: true
            )
            let sut = HangsView(
                events: [event], threshold: .constant(.milliseconds(250)), expanded: .constant(nil),
                onOpen: { _ in }, onMarkAllSeen: {}, onClear: {}
            )
            .environment(\.locale, Locale(identifier: "en_US"))
            .environment(\.timeZone, try #require(TimeZone(identifier: "UTC")))
            let expected = "Nov 16, 2025 at 10:46:40\u{202F}AM · MetricKit"

            let actual = try sut.inspect().find(ViewType.Text.self, where: { try $0.string().hasSuffix("MetricKit") }).string()

            #expect(actual == expected)
        }

        @Test("Opening a hang in the plugin marks it seen in the store, which clears the badge")
        func pluginMarksSeen() throws {
            var counts: [Int] = []
            let store = HangStore(threshold: .milliseconds(250)) { _ in } onUnseenCountChange: { counts.append($0) }
            store.add(HangEvent(
                id: UUID(), date: Date(timeIntervalSince1970: 1), duration: .milliseconds(612), frames: [], source: .detected, isSeen: false
            ))
            let sut = HangDetectorPluginView(store: store)

            try sut.inspect().find(button: "612 ms").tap()

            #expect(store.unseenCount == 0)
            #expect(counts == [1, 0])
        }

        @Test("Choosing a threshold in the plugin changes the store's, which the monitor follows")
        func pluginThreshold() throws {
            var thresholds: [Duration] = []
            let store = HangStore(threshold: .milliseconds(250)) { thresholds.append($0) }
            let sut = HangDetectorPluginView(store: store)

            try sut.inspect().find(ViewType.Picker.self).select(value: Duration.milliseconds(500))

            #expect(store.threshold == .milliseconds(500))
            #expect(thresholds == [.milliseconds(500)])
        }

        @Test("Frames in the app's executable are its own code, and the first of them is selected")
        func ownCode() throws {
            let event = HangEvent(
                id: UUID(), date: Date(timeIntervalSince1970: 1), duration: .milliseconds(612),
                frames: [
                    "0 libsystem_kernel.dylib 0x00000001842b5f30 __semwait_signal + 8",
                    "1 Example 0x0000000100004a1c $s7Example5blockyyF + 48",
                    "2 Example 0x0000000100004b00 main + 8"
                ],
                source: .detected, isSeen: true
            )
            let sut = HangsView(
                events: [event], threshold: .constant(.milliseconds(250)), expanded: .constant(event.id), ownImage: "Example",
                onOpen: { _ in }, onMarkAllSeen: {}, onClear: {}
            )
            let expectedOwn = [false, true, true]
            let expectedSelected = [false, true, false]
            let expectedSymbols = ["__semwait_signal", "$s7Example5blockyyF", "main"]

            let rows = try sut.inspect().findAll(DebugDrawerStackFrameRow.self).map { try $0.actualView() }

            #expect(rows.map(\.isOwnCode) == expectedOwn)
            #expect(rows.map(\.isSelected) == expectedSelected)
            #expect(rows.map(\.symbol) == expectedSymbols)
        }

        @Test("The header counts the hangs with a warning glyph, following the store, and shows nothing without one")
        func headerAccessory() throws {
            let store = HangStore(threshold: .milliseconds(250))
            let sut = HangDetectorPlugin(store: store, ownImage: "Example")
            let expected = "2 warnings"

            #expect(throws: (any Error).self) { try sut.headerAccessory.inspect().find(DebugDrawerIssueCount.self) }
            for milliseconds in [300, 400] {
                store.add(HangEvent(
                    id: UUID(), date: Date(timeIntervalSince1970: 1), duration: .milliseconds(milliseconds),
                    frames: [], source: .detected, isSeen: false
                ))
            }
            let actual = try sut.headerAccessory.inspect().find(DebugDrawerIssueCount.self).actualView()

            #expect(actual.severity == .warning)
            #expect(actual.spokenLabel == expected)
        }
    }
#endif
