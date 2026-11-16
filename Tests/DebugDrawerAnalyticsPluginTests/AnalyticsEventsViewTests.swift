// ViewInspector is linked on Apple platforms only, and the views are tested on the Mac.
#if os(macOS)
    @testable import DebugDrawer
    @testable import DebugDrawerAnalyticsPlugin
    import Foundation
    import SwiftUI
    import Testing
    import ViewInspector

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct AnalyticsEventsViewTests {
        @Test("With no events the plugin says how they arrive, and offers no filter or buttons")
        func empty() throws {
            let sut = AnalyticsEventsView(
                events: [], capacity: 10, query: .constant(""), selected: .constant(nil), redaction: .none, onClear: {}
            )
            let expected = "No events yet. Each one the app passes to AnalyticsEvents.record shows here as it is sent."

            let actual = try sut.inspect().find(text: expected).string()

            #expect(actual == expected)
            #expect(throws: (any Error).self) { try sut.inspect().find(button: "Clear") }
            #expect(throws: (any Error).self) { try sut.inspect().find(ViewType.TextField.self) }
        }

        @Test("Each event shows its name, its time to the millisecond in the view's locale and time zone, and its source and property count")
        func row() throws {
            let event = AnalyticsEvent(
                id: 1, timestamp: Date(timeIntervalSince1970: 1_763_290_000.25), name: "checkout_completed",
                properties: ["plan": "pro", "seats": 3], source: "Segment"
            )
            let sut = AnalyticsEventsView(
                events: [event], capacity: 10, query: .constant(""), selected: .constant(nil), redaction: .none, onClear: {}
            )
            .environment(\.locale, Locale(identifier: "en_US"))
            .environment(\.timeZone, try #require(TimeZone(identifier: "UTC")))
            let expectedTime = "10:46:40.250\u{202F}AM"

            let name = try sut.inspect().find(text: "checkout_completed").string()
            let time = try sut.inspect().find(ViewType.Text.self, where: { try $0.string().hasPrefix("10:46") }).string()
            let summary = try sut.inspect().find(text: "Segment · 2 properties").string()

            #expect(name == "checkout_completed")
            #expect(time == expectedTime)
            #expect(summary == "Segment · 2 properties")
        }

        @Test("Events are listed in the order given, the newest first")
        func order() throws {
            let events = [
                AnalyticsEvent(id: 2, timestamp: Date(timeIntervalSince1970: 1), name: "second", properties: [:], source: nil),
                AnalyticsEvent(id: 1, timestamp: Date(timeIntervalSince1970: 0), name: "first", properties: ["a": 1], source: nil)
            ]
            let sut = AnalyticsEventsView(
                events: events, capacity: 10, query: .constant(""), selected: .constant(nil), redaction: .none, onClear: {}
            )
            let expected = ["second", "first"]

            let actual = try sut.inspect().findAll(AnalyticsEventRow.self).map { try $0.actualView().event.name }

            #expect(actual == expected)
        }

        @Test("The filter lists only the events whose name, key or value matches")
        func filter() throws {
            let events = [
                AnalyticsEvent(id: 3, timestamp: Date(timeIntervalSince1970: 2), name: "signed_up", properties: ["plan": "pro"], source: nil),
                AnalyticsEvent(id: 2, timestamp: Date(timeIntervalSince1970: 1), name: "opened", properties: [:], source: nil),
                AnalyticsEvent(id: 1, timestamp: Date(timeIntervalSince1970: 0), name: "upgraded", properties: ["to": ["plan": "team"]], source: nil)
            ]
            let sut = AnalyticsEventsView(
                events: events, capacity: 10, query: .constant("PLAN"), selected: .constant(nil), redaction: .none, onClear: {}
            )
            let expected = ["signed_up", "upgraded"]

            let actual = try sut.inspect().findAll(AnalyticsEventRow.self).map { try $0.actualView().event.name }

            #expect(actual == expected)
        }

        @Test("Typing in the filter field changes the filter")
        func filterField() throws {
            let event = AnalyticsEvent(id: 1, timestamp: Date(timeIntervalSince1970: 0), name: "opened", properties: [:], source: nil)
            var query = ""
            let sut = AnalyticsEventsView(
                events: [event], capacity: 10, query: Binding(get: { query }, set: { query = $0 }), selected: .constant(nil),
                redaction: .none, onClear: {}
            )

            try sut.inspect().find(ViewType.TextField.self).setInput("checkout")

            #expect(query == "checkout")
        }

        @Test("A filter that matches nothing says so, and still offers Clear")
        func filterNoMatch() throws {
            let event = AnalyticsEvent(id: 1, timestamp: Date(timeIntervalSince1970: 0), name: "opened", properties: [:], source: nil)
            let sut = AnalyticsEventsView(
                events: [event], capacity: 10, query: .constant(" refund "), selected: .constant(nil), redaction: .none, onClear: {}
            )
            let expected = "No events match “refund”."

            let actual = try sut.inspect().find(text: expected).string()

            #expect(actual == expected)
            #expect(try sut.inspect().findAll(AnalyticsEventRow.self).isEmpty)
            #expect(try sut.inspect().find(button: "Clear").isDisabled() == false)
        }

        @Test("A full log says the oldest events are dropped; one with room says nothing")
        func capacityNote() throws {
            let events = (1 ... 3).reversed().map { id in
                AnalyticsEvent(id: id, timestamp: Date(timeIntervalSince1970: 0), name: "e\(id)", properties: [:], source: nil)
            }
            let full = AnalyticsEventsView(
                events: events, capacity: 3, query: .constant(""), selected: .constant(nil), redaction: .none, onClear: {}
            )
            let roomy = AnalyticsEventsView(
                events: events, capacity: 4, query: .constant(""), selected: .constant(nil), redaction: .none, onClear: {}
            )
            let expected = "The newest 3 events are kept; older ones are dropped."

            let actual = try full.inspect().find(text: expected).string()

            #expect(actual == expected)
            #expect(throws: (any Error).self) { try roomy.inspect().find(text: expected) }
        }

        @Test("Tapping an event selects it; tapping it again clears the selection")
        func toggle() throws {
            let event = AnalyticsEvent(id: 7, timestamp: Date(timeIntervalSince1970: 0), name: "opened", properties: [:], source: nil)
            var selected: AnalyticsEvent.ID?
            let sut = AnalyticsEventsView(
                events: [event], capacity: 10, query: .constant(""), selected: Binding(get: { selected }, set: { selected = $0 }),
                redaction: .none, onClear: {}
            )

            try sut.inspect().find(AnalyticsEventRow.self).find(ViewType.Button.self).tap()

            #expect(selected == 7)

            try sut.inspect().find(AnalyticsEventRow.self).find(ViewType.Button.self).tap()

            #expect(selected == nil)
        }

        @Test("The selected event is marked selected; below the list, each property as a key and value sorted by key, its JSON and Copy JSON")
        func selectedDetail() throws {
            let event = AnalyticsEvent(
                id: 1, timestamp: Date(timeIntervalSince1970: 0), name: "checkout_completed",
                properties: ["seats": 3, "plan": "pro", "items": ["sku-1"]], source: nil
            )
            let sut = AnalyticsEventsView(
                events: [event], capacity: 10, query: .constant(""), selected: .constant(1), redaction: .none, onClear: {}
            )
            let expectedKeys = ["items", "plan", "seats"]
            let expectedValues = [#"["sku-1"]"#, "pro", "3"]

            let rows = try sut.inspect().findAll(DebugDrawerKeyValueRow.self)
            let keys = try rows.map { try $0.actualView().label }
            let values = try rows.map { try $0.actualView().value }
            let json = try sut.inspect().find(text: event.formattedJSON).string()

            #expect(keys == expectedKeys)
            #expect(values == expectedValues)
            #expect(json == event.formattedJSON)
            #expect(try sut.inspect().find(button: "Copy JSON").labelView().text().string() == "Copy JSON")
            #expect(try sut.inspect().find(AnalyticsEventRow.self).actualView().isSelected)
            #expect(throws: (any Error).self) {
                try sut.inspect().find(ViewType.ScrollView.self).find(AnalyticsEventDetail.self)
            }
        }

        @Test("The close button beside the selected event's name clears the selection")
        func close() throws {
            let event = AnalyticsEvent(id: 4, timestamp: Date(timeIntervalSince1970: 0), name: "opened", properties: [:], source: nil)
            var selected: AnalyticsEvent.ID? = 4
            let sut = AnalyticsEventsView(
                events: [event], capacity: 10, query: .constant(""), selected: Binding(get: { selected }, set: { selected = $0 }),
                redaction: .none, onClear: {}
            )

            try sut.inspect().find(AnalyticsEventDetail.self).find(ViewType.Button.self).tap()

            #expect(selected == nil)
        }

        @Test("A selected event the filter hides shows no detail")
        func selectedFilteredOut() throws {
            let event = AnalyticsEvent(id: 4, timestamp: Date(timeIntervalSince1970: 0), name: "opened", properties: [:], source: nil)
            let sut = AnalyticsEventsView(
                events: [event], capacity: 10, query: .constant("refund"), selected: .constant(4), redaction: .none, onClear: {}
            )

            #expect(throws: (any Error).self) { try sut.inspect().find(AnalyticsEventDetail.self) }
        }

        @Test("With no event selected no properties or JSON show")
        func collapsed() throws {
            let event = AnalyticsEvent(id: 1, timestamp: Date(timeIntervalSince1970: 0), name: "opened", properties: ["plan": "pro"], source: nil)
            let sut = AnalyticsEventsView(
                events: [event], capacity: 10, query: .constant(""), selected: .constant(nil), redaction: .none, onClear: {}
            )

            #expect(throws: (any Error).self) { try sut.inspect().find(DebugDrawerKeyValueRow.self) }
            #expect(throws: (any Error).self) { try sut.inspect().find(button: "Copy JSON") }
        }

        @Test("The selected event masks the values the redaction rules call sensitive until revealed")
        func redaction() throws {
            let event = AnalyticsEvent(
                id: 1, timestamp: Date(timeIntervalSince1970: 0), name: "signed_in", properties: ["auth_token": "t0k3n"], source: nil
            )
            let sut = AnalyticsEventsView(
                events: [event], capacity: 10, query: .constant(""), selected: .constant(1), redaction: .standard, onClear: {}
            )

            let row = try sut.inspect().find(DebugDrawerKeyValueRow.self).actualView()
            let json = try sut.inspect().find(RedactedText.self, where: { try $0.actualView().value == event.formattedJSON }).actualView()

            #expect(row.value == "t0k3n")
            #expect(row.redacted == DebugDrawerRedaction.mask)
            #expect(json.redacted == event.formattedJSON(redaction: .standard))
            #expect(json.redacted.contains(DebugDrawerRedaction.mask))
        }

        @Test("Export All is offered beside Clear, and Clear clears the selection and the events")
        func clear() throws {
            let event = AnalyticsEvent(id: 1, timestamp: Date(timeIntervalSince1970: 0), name: "opened", properties: [:], source: nil)
            var selected: AnalyticsEvent.ID? = 1
            var clears = 0
            let sut = AnalyticsEventsView(
                events: [event], capacity: 10, query: .constant(""), selected: Binding(get: { selected }, set: { selected = $0 }),
                redaction: .none, onClear: { clears += 1 }
            )

            try sut.inspect().find(button: "Clear").tap()

            #expect(clears == 1)
            #expect(selected == nil)
            #expect(try sut.inspect().find(text: "Export All").string() == "Export All")
        }

        @Test("The header counts the events, and shows nothing before the first")
        func headerAccessory() throws {
            let log = AnalyticsEventLog(capacity: 2000)
            let model = AnalyticsEventsModel(log: log)
            let sut = AnalyticsHeaderAccessory(model: model)

            #expect(throws: (any Error).self) { try sut.inspect().find(ViewType.Text.self) }

            log.record(name: "a", properties: [:], source: nil)
            model.reload()

            #expect(try sut.inspect().find(ViewType.Text.self).string() == "1 event")

            for _ in 0 ..< 1203 {
                log.record(name: "b", properties: [:], source: nil)
            }
            model.reload()

            #expect(try sut.inspect().find(ViewType.Text.self).string(locale: Locale(identifier: "en_US")) == "1,204 events")
        }

        @Test("The plugin's list on screen sees every event, which clears the badge")
        func pluginMarksSeen() throws {
            let log = AnalyticsEventLog(capacity: 10)
            log.record(name: "opened", properties: [:], source: nil)
            var counts: [Int] = []
            let model = AnalyticsEventsModel(log: log) { counts.append($0) }
            let sut = AnalyticsPluginView(model: model)

            try sut.inspect().find(AnalyticsEventsView.self).callOnAppear()

            #expect(model.unseenCount == 0)
            #expect(counts == [1, 0])
        }
    }
#endif
