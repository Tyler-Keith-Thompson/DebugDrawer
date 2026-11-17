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
    struct NetworkConditionViewTests {
        @Test("While a profile is on, the header indicator counts the profiles on and names them to VoiceOver; while none is, it is gone")
        func headerIndicator() throws {
            let entries = [
                NetworkEntry(timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000), method: "GET", url: "", host: "", path: "",
                             requestHeaders: [:], requestBody: nil, statusCode: 200, isComplete: true)
            ]
            let profiles = [NetworkConditionProfile(name: "3G"), NetworkConditionProfile(name: "Lossy", isEnabled: false)]
            let sut = NetworkHeaderSummary(entries: entries, conditions: profiles)
            let none = NetworkHeaderSummary(entries: entries, conditions: [NetworkConditionProfile(name: "3G", isEnabled: false)])
            let expected = "1 active"

            let actual = try sut.inspect().find(NetworkConditionsIndicator.self).find(text: expected).string()
            let label = try sut.inspect().find(NetworkConditionsIndicator.self).find(ViewType.HStack.self).accessibilityLabel().string()

            #expect(actual == expected)
            #expect(label == "Network conditions: 3G active")
            #expect(throws: (any Error).self) { try none.inspect().find(textWhere: { text, _ in text.hasSuffix("active") }) }
        }

        @Test("The HUD readout shows the indicator while a profile is on, so it shows with the drawer closed, and says so while none is")
        func hudReadout() throws {
            let active = NetworkConditionsHUDReadout(summary: "2 conditions active")
            let inactive = NetworkConditionsHUDReadout(summary: nil)

            let actualActive = try active.inspect().find(NetworkConditionsIndicator.self).find(text: "2 conditions active").string()
            let actualInactive = try inactive.inspect().find(text: "Network unconditioned").string()

            #expect(actualActive == "2 conditions active")
            #expect(actualInactive == "Network unconditioned")
            #expect(throws: (any Error).self) { try inactive.inspect().find(NetworkConditionsIndicator.self).find(ViewType.HStack.self) }
        }

        @Test("The plugin offers a HUD readout, so the indicator can be pinned")
        func pluginHasHUD() {
            let sut = AnyDebugDrawerPlugin(NetworkPlugin())

            #expect(sut.hasHUD)
        }

        @Test("Each profile is a row with its name, effect and hosts; its switch turns it on and off")
        func rows() throws {
            let threeG = NetworkConditionProfile(name: "3G", host: .exact("api.example.com"), latency: .milliseconds(100), bandwidth: 97500)
            let lossy = NetworkConditionProfile(name: "Lossy", isEnabled: false, latency: .milliseconds(500), failureRate: 10, failure: .timedOut)
            var changes: [String] = []
            let sut = NetworkConditionsSection(
                profiles: [threeG, lossy], issue: nil, selected: .constant(nil),
                setEnabled: { id, isOn in changes.append("\(id == threeG.id ? "3G" : "Lossy") \(isOn)") },
                add: {}, edit: { _ in }, move: { _, _ in }, delete: { _ in }
            )
            let expectedTexts = ["3G", "100 ms · 97.5 KB/s", "api.example.com", "Lossy", "500 ms · 10% timeout", "all hosts"]

            let rows = try sut.inspect().findAll(NetworkConditionRow.self)
            let texts = try expectedTexts.map { try sut.inspect().find(text: $0).string() }
            try rows[0].find(ViewType.Toggle.self).tap()
            try rows[1].find(ViewType.Toggle.self).tap()

            #expect(rows.count == 2)
            #expect(texts == expectedTexts)
            #expect(changes == ["3G false", "Lossy true"])
        }

        @Test("With no profiles the section says what one does, and Add Condition adds")
        func empty() throws {
            var adds = 0
            let sut = NetworkConditionsSection(
                profiles: [], issue: nil, selected: .constant(nil),
                setEnabled: { _, _ in }, add: { adds += 1 }, edit: { _ in }, move: { _, _ in }, delete: { _ in }
            )

            _ = try sut.inspect().find(text: "No conditions. Add one to slow down or fail the requests to a host.")
            try sut.inspect().find(button: "Add Condition").tap()

            #expect(adds == 1)
        }

        @Test("A selected profile offers Edit, Move Up, Move Down and Delete, the ends' moves unavailable")
        func selectedActions() throws {
            let first = NetworkConditionProfile(name: "First")
            let second = NetworkConditionProfile(name: "Second")
            var selected: NetworkConditionProfile.ID? = first.id
            var events: [String] = []
            let sut = NetworkConditionsSection(
                profiles: [first, second], issue: nil, selected: Binding(get: { selected }, set: { selected = $0 }),
                setEnabled: { _, _ in }, add: {},
                edit: { events.append("edit \($0.name)") },
                move: { _, offset in events.append("move \(offset)") },
                delete: { _ in events.append("delete") }
            )

            let isMoveUpDisabled = try sut.inspect().find(button: "Move Up").isDisabled()
            let isMoveDownDisabled = try sut.inspect().find(button: "Move Down").isDisabled()
            try sut.inspect().find(button: "Edit").tap()
            try sut.inspect().find(button: "Move Down").tap()
            try sut.inspect().find(button: "Delete").tap()

            #expect(isMoveUpDisabled)
            #expect(!isMoveDownDisabled)
            #expect(events == ["edit First", "move 1", "delete"])
            #expect(selected == nil)
        }

        @Test("A problem reading the saved profiles shows above the list, about the conditions")
        func issue() throws {
            let sut = NetworkConditionsSection(
                profiles: [], issue: .unreadable, selected: .constant(nil),
                setEnabled: { _, _ in }, add: {}, edit: { _ in }, move: { _, _ in }, delete: { _ in }
            )
            let expected = "The saved conditions couldn't be read, so none are loaded."

            let actual = try sut.inspect().find(text: expected).string()

            #expect(actual == expected)
        }

        @Test("A preset fills the editor's fields; a latency that isn't a number holds Save back until it is fixed, then Save saves")
        func editorPresetAndSave() async throws {
            var saved: [NetworkConditionProfile] = []
            var draft = NetworkConditionDraft.new()
            draft.latency = "soon"
            let sut = NetworkConditionEditor(draft: draft, cancel: {}, save: { saved.append($0) })
            var disabledBefore = false
            var disabledAfter = true

            try await ViewHosting.host(sut) {
                try await sut.inspection.inspect { view in
                    disabledBefore = try view.find(button: "Save").isDisabled()
                    try view.find(button: "3G").tap()
                }
                try await sut.inspection.inspect { view in
                    disabledAfter = try view.find(button: "Save").isDisabled()
                    try view.find(button: "Save").tap()
                }
            }

            #expect(disabledBefore)
            #expect(!disabledAfter)
            let actual = try #require(saved.first)
            #expect(actual.name == "3G")
            #expect(actual.latency == .milliseconds(100))
            #expect(actual.bandwidth == 97500)
            #expect(actual.host == .any)
        }

        @Test("A conditioned request shows Conditioned beside its status and, selected, the profile and what it did")
        func conditionedRow() throws {
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000), method: "GET",
                url: "https://api.example.com/v1/orders", host: "api.example.com", path: "/v1/orders",
                requestHeaders: [:], requestBody: nil, duration: 2.01, error: "The request timed out.", isComplete: true,
                conditionEffect: NetworkConditionEffect(profileName: "Offline", latency: .milliseconds(2000), bandwidth: nil, failure: .timedOut)
            )
            let sut = NetworkRequestRow(entry: entry, redaction: .standard, isSelected: true, onSelect: {}, onMock: { _ in })
            let plain = NetworkRequestRow(entry: NetworkEntry(
                timestamp: entry.timestamp, method: "GET", url: entry.url, host: entry.host, path: entry.path,
                requestHeaders: [:], requestBody: nil, statusCode: 200, isComplete: true
            ), redaction: .standard, isSelected: false, onSelect: {})

            let badge = try sut.inspect().find(NetworkConditionedBadge.self).find(text: "Conditioned").string()
            let profile = try sut.inspect()
                .find(DebugDrawerKeyValueRow.self, where: { try $0.actualView().label == "Conditioned by" }).actualView().value
            let effect = try sut.inspect().find(DebugDrawerKeyValueRow.self, where: { try $0.actualView().label == "Condition" }).actualView().value

            #expect(badge == "Conditioned")
            #expect(profile == "Offline")
            #expect(effect == "Delayed 2,000 ms · Failed: timeout")
            #expect(throws: (any Error).self) { try plain.inspect().find(NetworkConditionedBadge.self) }
        }
    }
#endif
