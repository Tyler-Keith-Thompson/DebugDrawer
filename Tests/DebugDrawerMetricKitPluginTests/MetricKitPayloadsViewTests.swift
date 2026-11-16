// ViewInspector is linked on Apple platforms only, and the views are tested on the Mac.
#if os(macOS)
    @testable import DebugDrawerMetricKitPlugin
    import Foundation
    import SwiftUI
    import Testing
    import ViewInspector

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct MetricKitPayloadsViewTests {
        @Test("With no payloads the plugin says when they arrive, and offers no buttons")
        func empty() throws {
            let sut = MetricKitPayloadsView(
                payloads: [], expanded: .constant(nil), onOpen: { _ in }, onDelete: { _ in }, onMarkAllSeen: {}, onDeleteAll: {}
            )
            let expected = "No MetricKit payloads. A device delivers metrics about once a day and diagnostics as they happen; the simulator, none."

            let actual = try sut.inspect().find(text: expected).string()

            #expect(actual == expected)
            #expect(throws: (any Error).self) { try sut.inspect().find(button: "Delete All") }
        }

        @Test("Each payload shows its kind, its summary and its period in the view's locale and time zone")
        func row() throws {
            let payload = MetricKitPayload(
                id: UUID(), kind: .metrics, begin: Date(timeIntervalSince1970: 1_763_164_800), end: Date(timeIntervalSince1970: 1_763_251_200),
                received: Date(timeIntervalSince1970: 1_763_290_000), json: Data(#"{"appVersion":"1.2","cpuMetrics":{}}"#.utf8), isSeen: true
            )
            let sut = MetricKitPayloadsView(
                payloads: [payload], expanded: .constant(nil), onOpen: { _ in }, onDelete: { _ in }, onMarkAllSeen: {}, onDeleteAll: {}
            )
            .environment(\.locale, Locale(identifier: "en_US"))
            .environment(\.timeZone, try #require(TimeZone(identifier: "UTC")))
            let expectedPeriod = "Nov 15, 2025 at 12:00\u{202F}AM\u{2009}–\u{2009}Nov 16, 2025 at 12:00\u{202F}AM"

            let kind = try sut.inspect().find(text: "Metrics").string()
            let summary = try sut.inspect().find(text: "App 1.2 · 1 metric group").string()
            let period = try sut.inspect().find(ViewType.Text.self, where: { try $0.string().hasPrefix("Nov 15") }).string()

            #expect(kind == "Metrics")
            #expect(summary == "App 1.2 · 1 metric group")
            #expect(period == expectedPeriod)
        }

        @Test("Tapping a payload opens it and reports it opened; tapping it again closes it")
        func toggle() throws {
            let payload = MetricKitPayload(
                id: UUID(), kind: .diagnostics, begin: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 1),
                received: Date(timeIntervalSince1970: 1), json: Data(#"{"crashDiagnostics":[{}]}"#.utf8), isSeen: false
            )
            var expanded: MetricKitPayload.ID?
            var opened: [MetricKitPayload.ID] = []
            let sut = MetricKitPayloadsView(
                payloads: [payload],
                expanded: Binding(get: { expanded }, set: { expanded = $0 }),
                onOpen: { opened.append($0) }, onDelete: { _ in }, onMarkAllSeen: {}, onDeleteAll: {}
            )

            try sut.inspect().find(button: "Diagnostics").tap()

            #expect(expanded == payload.id)
            #expect(opened == [payload.id])

            try sut.inspect().find(button: "Diagnostics").tap()

            #expect(expanded == nil)
            #expect(opened == [payload.id])
        }

        @Test("An open payload shows its formatted JSON, a button that copies it and one that exports it")
        func expandedShowsJSON() throws {
            let payload = MetricKitPayload(
                id: UUID(), kind: .metrics, begin: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 1),
                received: Date(timeIntervalSince1970: 1), json: Data(#"{"b":2,"a":1}"#.utf8), isSeen: true
            )
            let sut = MetricKitPayloadsView(
                payloads: [payload], expanded: .constant(payload.id), onOpen: { _ in }, onDelete: { _ in }, onMarkAllSeen: {}, onDeleteAll: {}
            )
            let expected = "{\n  \"a\" : 1,\n  \"b\" : 2\n}"

            let actual = try sut.inspect().find(text: expected).string()

            #expect(actual == expected)
            #expect(try sut.inspect().find(button: "Copy JSON").labelView().text().string() == "Copy JSON")
            #expect(try sut.inspect().find(text: "Export").string() == "Export")
        }

        @Test("A closed payload shows no JSON")
        func collapsedHidesJSON() throws {
            let payload = MetricKitPayload(
                id: UUID(), kind: .metrics, begin: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 1),
                received: Date(timeIntervalSince1970: 1), json: Data(#"{"a":1}"#.utf8), isSeen: true
            )
            let sut = MetricKitPayloadsView(
                payloads: [payload], expanded: .constant(nil), onOpen: { _ in }, onDelete: { _ in }, onMarkAllSeen: {}, onDeleteAll: {}
            )

            #expect(throws: (any Error).self) { try sut.inspect().find(text: "{\n  \"a\" : 1\n}") }
            #expect(throws: (any Error).self) { try sut.inspect().find(button: "Copy JSON") }
        }

        @Test("An unopened payload is tagged New; an opened one isn't")
        func newTag() throws {
            let unseen = MetricKitPayload(
                id: UUID(), kind: .metrics, begin: Date(timeIntervalSince1970: 1), end: Date(timeIntervalSince1970: 2),
                received: Date(timeIntervalSince1970: 2), json: Data("{}".utf8), isSeen: false
            )
            let seen = MetricKitPayload(
                id: UUID(), kind: .diagnostics, begin: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 1),
                received: Date(timeIntervalSince1970: 1), json: Data("{}".utf8), isSeen: true
            )
            let sut = MetricKitPayloadsView(
                payloads: [unseen, seen], expanded: .constant(nil), onOpen: { _ in }, onDelete: { _ in }, onMarkAllSeen: {}, onDeleteAll: {}
            )

            let actual = try sut.inspect().findAll(ViewType.Text.self, where: { try $0.string() == "New" })

            #expect(actual.count == 1)
            #expect(try actual.first?.accessibilityLabel().string() == "New payload")
        }

        @Test("A payload's delete button, labelled with its kind and period, deletes that payload")
        func deleteOne() throws {
            let payload = MetricKitPayload(
                id: UUID(), kind: .diagnostics, begin: Date(timeIntervalSince1970: 1_763_290_000), end: Date(timeIntervalSince1970: 1_763_290_000),
                received: Date(timeIntervalSince1970: 1_763_290_000), json: Data("{}".utf8), isSeen: false
            )
            var deleted: [MetricKitPayload.ID] = []
            let sut = MetricKitPayloadsView(
                payloads: [payload], expanded: .constant(nil), onOpen: { _ in }, onDelete: { deleted.append($0) }, onMarkAllSeen: {}, onDeleteAll: {}
            )
            .environment(\.locale, Locale(identifier: "en_US"))
            .environment(\.timeZone, try #require(TimeZone(identifier: "UTC")))

            let button = try sut.inspect().find(ViewType.Button.self) { button in
                try button.accessibilityLabel().string().hasPrefix("Delete diagnostics payload of Nov 16, 2025")
            }
            try button.tap()

            #expect(deleted == [payload.id])
        }

        @Test("Delete All and Mark All Seen call their actions")
        func buttons() throws {
            let payload = MetricKitPayload(
                id: UUID(), kind: .metrics, begin: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 1),
                received: Date(timeIntervalSince1970: 1), json: Data("{}".utf8), isSeen: false
            )
            var calls: [String] = []
            let sut = MetricKitPayloadsView(
                payloads: [payload], expanded: .constant(nil), onOpen: { _ in }, onDelete: { _ in },
                onMarkAllSeen: { calls.append("seen") }, onDeleteAll: { calls.append("delete") }
            )

            try sut.inspect().find(button: "Mark All Seen").tap()
            try sut.inspect().find(button: "Delete All").tap()

            #expect(calls == ["seen", "delete"])
        }

        @Test("Mark All Seen is disabled once every payload is seen")
        func markAllSeenDisabled() throws {
            let payload = MetricKitPayload(
                id: UUID(), kind: .metrics, begin: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 1),
                received: Date(timeIntervalSince1970: 1), json: Data("{}".utf8), isSeen: true
            )
            let sut = MetricKitPayloadsView(
                payloads: [payload], expanded: .constant(nil), onOpen: { _ in }, onDelete: { _ in }, onMarkAllSeen: {}, onDeleteAll: {}
            )

            let actual = try sut.inspect().find(button: "Mark All Seen").isDisabled()

            #expect(actual)
        }

        @Test("Opening a payload in the plugin marks it seen in the store, which clears the badge")
        func pluginMarksSeen() throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            var counts: [Int] = []
            let store = MetricKitPayloadStore(directory: directory) { counts.append($0) }
            store.receive([ReceivedMetricKitPayload(kind: .diagnostics, json: Data("{}".utf8))])
            let sut = MetricKitPluginView(store: store)

            try sut.inspect().find(button: "Diagnostics").tap()

            #expect(store.unseenCount == 0)
            #expect(counts == [1, 0])
        }
    }
#endif
