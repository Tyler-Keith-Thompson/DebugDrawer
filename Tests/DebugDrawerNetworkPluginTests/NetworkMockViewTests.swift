// ViewInspector is linked on Apple platforms only, and the views are tested on the Mac.
#if os(macOS)
    @testable import DebugDrawer
    @testable import DebugDrawerNetworkPlugin
    import Foundation
    import SwiftUI
    import Testing
    import ViewInspector

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct NetworkMockViewTests {
        @Test("Each rule is a row with its name, methods, pattern and status; its switch turns it on and off")
        func rows() throws {
            let greeting = NetworkMockRule(
                name: "Greeting", matcher: .init(methods: ["GET"], host: .exact("api.example.com"), path: .wildcard("/v1/greeting/*")),
                response: .init(status: 200)
            )
            let outage = NetworkMockRule(name: "Outage", isEnabled: false, matcher: .init(path: .regex("/v1/.*")), response: .init(status: 503))
            var changes: [String] = []
            let sut = NetworkMocksSection(
                rules: [greeting, outage], issue: nil, selected: .constant(nil),
                setEnabled: { id, isOn in changes.append("\(id == greeting.id ? "Greeting" : "Outage") \(isOn)") },
                add: {}, edit: { _ in }, move: { _, _ in }, delete: { _ in }
            )
            let expectedTexts = ["Greeting", "GET", "api.example.com/v1/greeting/*", "200", "Outage", "ANY", "any host · regex /v1/.*", "503"]

            let rows = try sut.inspect().findAll(NetworkMockRuleRow.self)
            let texts = try expectedTexts.map { try sut.inspect().find(text: $0).string() }
            try rows[0].find(ViewType.Toggle.self).tap()
            try rows[1].find(ViewType.Toggle.self).tap()

            #expect(rows.count == 2)
            #expect(texts == expectedTexts)
            #expect(changes == ["Greeting false", "Outage true"])
        }

        @Test("With no rules the section says how to add one, and Add Mock adds")
        func empty() throws {
            var adds = 0
            let sut = NetworkMocksSection(
                rules: [], issue: nil, selected: .constant(nil),
                setEnabled: { _, _ in }, add: { adds += 1 }, edit: { _ in }, move: { _, _ in }, delete: { _ in }
            )

            _ = try sut.inspect().find(text: "No mocks. Add one, or open a request and choose Mock This to answer it without the server.")
            try sut.inspect().find(button: "Add Mock").tap()

            #expect(adds == 1)
        }

        @Test("Tapping a rule selects it; a selected rule offers Edit, Move Up, Move Down and Delete, the ends' moves unavailable")
        func selectedActions() throws {
            let first = NetworkMockRule(name: "First", matcher: .init(), response: .init())
            let second = NetworkMockRule(name: "Second", matcher: .init(), response: .init())
            var selected: NetworkMockRule.ID?
            var events: [String] = []
            let unselected = NetworkMocksSection(
                rules: [first, second], issue: nil, selected: Binding(get: { selected }, set: { selected = $0 }),
                setEnabled: { _, _ in }, add: {}, edit: { _ in }, move: { _, _ in }, delete: { _ in }
            )
            try unselected.inspect().findAll(NetworkMockRuleRow.self)[0].find(ViewType.Button.self).tap()
            let sut = NetworkMocksSection(
                rules: [first, second], issue: nil, selected: Binding(get: { selected }, set: { selected = $0 }),
                setEnabled: { _, _ in }, add: {},
                edit: { events.append("edit \($0.name)") },
                move: { _, offset in events.append("move \(offset)") },
                delete: { _ in events.append("delete") }
            )

            let moveDown = try sut.inspect().find(button: "Move Down")
            let isMoveUpDisabled = try sut.inspect().find(button: "Move Up").isDisabled()
            let isMoveDownDisabled = moveDown.isDisabled()
            try sut.inspect().find(button: "Edit").tap()
            try moveDown.tap()
            try sut.inspect().find(button: "Delete").tap()

            #expect(isMoveUpDisabled)
            #expect(!isMoveDownDisabled)
            #expect(events == ["edit First", "move 1", "delete"])
            #expect(selected == nil)
        }

        @Test("A problem reading the saved rules shows above the list")
        func issue() throws {
            let sut = NetworkMocksSection(
                rules: [], issue: .unsupportedVersion(3), selected: .constant(nil),
                setEnabled: { _, _ in }, add: {}, edit: { _ in }, move: { _, _ in }, delete: { _ in }
            )
            let expected = NetworkMocksIssue.unsupportedVersion(3).message

            let actual = try sut.inspect().find(text: expected).string()

            #expect(actual == expected)
        }

        @Test("An invalid regex says so below its field, and Save stays unavailable until it is fixed")
        func invalidRegexInline() async throws {
            var draft = NetworkMockDraft.new()
            draft.pathKind = .regex
            draft.path = "/users/(\\d+"
            var saved: [NetworkMockRule] = []
            let sut = NetworkMockEditor(draft: draft, importBody: { _ in nil }, cancel: {}, save: { saved.append($0) })
            var problemShown = false
            var disabledBefore = false
            var disabledAfter = true

            try await ViewHosting.host(sut) {
                try await sut.inspection.inspect { view in
                    problemShown = (try? view.find(textWhere: { text, _ in text.hasPrefix("Not a valid regular expression") })) != nil
                    disabledBefore = try view.find(button: "Save").isDisabled()
                    try view.find(ViewType.TextField.self, where: { try $0.accessibilityLabel().string() == "Path" }).setInput("/users/(\\d+)")
                }
                try await sut.inspection.inspect { view in
                    disabledAfter = try view.find(button: "Save").isDisabled()
                    try view.find(button: "Save").tap()
                }
            }

            #expect(problemShown)
            #expect(disabledBefore)
            #expect(!disabledAfter)
            #expect(saved.map(\.matcher.path) == [.regex("/users/(\\d+)")])
            #expect(saved.first?.name == "ANY any host · regex /users/(\\d+)")
        }

        @Test("Saving an edited rule keeps its id and hands over every field")
        func saveEdited() async throws {
            let rule = NetworkMockRule(
                name: "Greeting", matcher: .init(methods: ["GET"], host: .exact("api.test"), path: .exact("/hello"), query: ["lang": "en"]),
                response: .init(status: 200, headers: ["X-Mock": "1"], body: .text("hi"), contentType: "text/plain")
            )
            var saved: [NetworkMockRule] = []
            let sut = NetworkMockEditor(draft: NetworkMockDraft(rule, isNew: false), importBody: { _ in nil }, cancel: {}, save: { saved.append($0) })
            var title = ""

            try await ViewHosting.host(sut) {
                try await sut.inspection.inspect { view in
                    title = try view.find(text: "Edit Mock").string()
                    try view.find(ViewType.TextField.self, where: { try $0.accessibilityLabel().string() == "Status" }).setInput("404")
                }
                try await sut.inspection.inspect { view in
                    try view.find(button: "Save").tap()
                }
            }

            var expected = rule
            expected.response.status = 404
            #expect(title == "Edit Mock")
            #expect(saved == [expected])
        }

        @Test("A status outside 100 to 599 can't be saved")
        func badStatus() {
            var draft = NetworkMockDraft.new()
            let statuses = ["99", "100", "599", "600", "abc", ""]
            let expected = [false, true, true, false, false, false]

            let actual = statuses.map { status in
                draft.status = status
                return draft.rule != nil
            }

            #expect(actual == expected)
        }

        @Test("A file body can't be saved until a file is chosen")
        func fileBodyNeedsFile() {
            var draft = NetworkMockDraft.new()
            draft.bodyKind = .file
            let before = draft.rule
            draft.bodyFile = "body-1.json"

            let actual = draft.rule?.response.body

            #expect(before == nil)
            #expect(actual == .file("body-1.json"))
        }

        @Test("A complete request offers Mock This, which hands over the request")
        func mockThis() throws {
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000), method: "GET", url: "https://example.com/",
                host: "example.com", path: "/", requestHeaders: [:], requestBody: nil, statusCode: 200, isComplete: true
            )
            var mocked: [String] = []
            let sut = NetworkRequestDetail(entry: entry, redaction: .standard, onMock: { mocked.append($0.url) })

            try sut.inspect().find(button: "Mock This").tap()

            #expect(mocked == ["https://example.com/"])
        }

        @Test("A mocked request shows Mocked in its row and the rule in its detail, and offers no Mock This")
        func mockedRequest() throws {
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000), method: "GET", url: "https://api.example.com/v1/greeting",
                host: "api.example.com", path: "/v1/greeting", requestHeaders: [:], requestBody: nil, statusCode: 200, isComplete: true,
                mockRuleName: "Greeting"
            )
            let sut = NetworkRequestRow(entry: entry, redaction: .standard, isSelected: true, onSelect: {}, onMock: { _ in })
            let plain = NetworkRequestRow(entry: NetworkEntry(
                timestamp: entry.timestamp, method: "GET", url: entry.url, host: entry.host, path: entry.path,
                requestHeaders: [:], requestBody: nil, statusCode: 200, isComplete: true
            ), redaction: .standard, isSelected: false, onSelect: {})

            let badge = try sut.inspect().find(NetworkMockedBadge.self).find(text: "Mocked").string()
            let rule = try sut.inspect().find(DebugDrawerKeyValueRow.self, where: { try $0.actualView().label == "Mocked by" }).actualView().value

            #expect(badge == "Mocked")
            #expect(rule == "Greeting")
            #expect(throws: (any Error).self) { try sut.inspect().find(button: "Mock This") }
            #expect(throws: (any Error).self) { try plain.inspect().find(NetworkMockedBadge.self) }
        }

        @Test("The header summary counts the mocks that are on, when any are")
        func headerCountsMocks() throws {
            let entries = [
                NetworkEntry(timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000), method: "GET", url: "", host: "", path: "",
                             requestHeaders: [:], requestBody: nil, statusCode: 200, isComplete: true)
            ]
            let sut = NetworkHeaderSummary(entries: entries, activeMocks: 2)
            let one = NetworkHeaderSummary(entries: entries, activeMocks: 1)
            let none = NetworkHeaderSummary(entries: entries, activeMocks: 0)

            let actual = try sut.inspect().find(text: "2 mocks").string()
            let actualOne = try one.inspect().find(text: "1 mock").string()

            #expect(actual == "2 mocks")
            #expect(actualOne == "1 mock")
            #expect(throws: (any Error).self) { try none.inspect().find(textWhere: { text, _ in text.hasSuffix("mocks") || text.hasSuffix("mock") }) }
        }
    }
#endif
