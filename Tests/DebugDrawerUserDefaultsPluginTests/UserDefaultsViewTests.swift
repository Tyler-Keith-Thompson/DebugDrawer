// ViewInspector is linked on Apple platforms only, and the views are tested on the Mac.
#if os(macOS)
    import DebugDrawer
    @testable import DebugDrawerUserDefaultsPlugin
    import Foundation
    import SwiftUI
    import Testing
    import ViewInspector

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct UserDefaultsViewTests {
        @Test("With a suite named, the picker lists Standard and the suite, and picking the suite asks for it")
        func suitePicker() throws {
            final class Selection {
                var suite = UserDefaultsSuite.standard
            }
            let selection = Selection()
            let group = UserDefaultsSuite.named("group.com.example.shared")
            let sut = UserDefaultsBrowserView(
                suites: [.standard, group], selectedSuite: Binding(get: { selection.suite }, set: { selection.suite = $0 }),
                entries: [DefaultsEntry(key: "launchCount", value: .number(3))], keys: ["launchCount"],
                searchText: .constant(""), showOtherDomains: .constant(false), redaction: .standard,
                actions: UserDefaultsBrowserActions(set: { _, _ in }, add: { _, _ in }, remove: { _ in }, reload: {})
            )

            let view = try sut.inspect()
            try view.find(ViewType.Picker.self).select(value: group)

            #expect(throws: Never.self) { try view.find(text: "Standard") }
            #expect(throws: Never.self) { try view.find(text: "group.com.example.shared") }
            #expect(throws: Never.self) { try view.find(text: "launchCount") }
            #expect(selection.suite == group)
        }

        @Test("With no suite named, there is no picker")
        func noSuitePicker() throws {
            let sut = UserDefaultsBrowserView(
                suites: [.standard], selectedSuite: .constant(.standard), entries: [], keys: [],
                searchText: .constant(""), showOtherDomains: .constant(false), redaction: .standard,
                actions: UserDefaultsBrowserActions(set: { _, _ in }, add: { _, _ in }, remove: { _ in }, reload: {})
            )

            let actual = try? sut.inspect().find(ViewType.Picker.self)

            #expect(actual == nil)
        }

        @Test("Reload in the menu asks for the suite again")
        func reload() throws {
            var reloads = 0
            let sut = UserDefaultsBrowserView(
                suites: [.standard], selectedSuite: .constant(.standard), entries: [], keys: [],
                searchText: .constant(""), showOtherDomains: .constant(false), redaction: .standard,
                actions: UserDefaultsBrowserActions(set: { _, _ in }, add: { _, _ in }, remove: { _ in }, reload: { reloads += 1 })
            )

            try sut.inspect().find(button: "Reload").tap()

            #expect(reloads == 1)
        }

        @Test("Add Key opens the form in place of the toolbar; adding asks for the key and type, then the toolbar returns")
        func addKey() async throws {
            var added: [String] = []
            let sut = UserDefaultsBrowserView(
                suites: [.standard], selectedSuite: .constant(.standard), entries: [], keys: ["taken"],
                searchText: .constant(""), showOtherDomains: .constant(false), redaction: .standard,
                actions: UserDefaultsBrowserActions(set: { _, _ in }, add: { added.append("\($0) \($1.title)") }, remove: { _ in }, reload: {})
            )
            var formKeys: Set<String>?
            var hasToolbarAfter = false

            try await ViewHosting.host(sut) {
                try await sut.inspection.inspect { view in
                    try view.find(button: "Add Key").tap()
                }
                try await sut.inspection.inspect { view in
                    let form = try view.find(DefaultsAddKeyForm.self).actualView()
                    formKeys = form.existingKeys
                    form.add("launchedAt", .date)
                }
                try await sut.inspection.inspect { view in
                    hasToolbarAfter = (try? view.find(button: "Add Key")) != nil
                }
            }

            #expect(formKeys == ["taken"])
            #expect(added == ["launchedAt Date"])
            #expect(hasToolbarAfter)
        }

        @Test("The add form holds Add back for an empty key and says why for a taken one; a new key adds with the type picked")
        func addKeyForm() async throws {
            var added: [String] = []
            let sut = DefaultsAddKeyForm(existingKeys: ["taken"], cancel: {}, add: { added.append("\($0) \($1.title)") })
            var isAddDisabledWhenEmpty = false
            var isAddDisabledWhenTaken = false
            var problem = ""

            try await ViewHosting.host(sut) {
                try await sut.inspection.inspect { view in
                    isAddDisabledWhenEmpty = try view.find(button: "Add").isDisabled()
                    try view.find(ViewType.TextField.self).setInput("taken")
                }
                try await sut.inspection.inspect { view in
                    isAddDisabledWhenTaken = try view.find(button: "Add").isDisabled()
                    problem = try view.find(text: "“taken” is already a key here.").string()
                    try view.find(ViewType.TextField.self).setInput("launchedAt")
                    try view.find(ViewType.Picker.self).select(value: PropertyListType.date)
                }
                try await sut.inspection.inspect { view in
                    try view.find(button: "Add").tap()
                }
            }

            #expect(isAddDisabledWhenEmpty)
            #expect(isAddDisabledWhenTaken)
            #expect(problem == "“taken” is already a key here.")
            #expect(added == ["launchedAt Date"])
        }

        @Test("For an array's item, the add form asks no key and adds with the type picked")
        func addItemForm() async throws {
            var added: [String] = []
            let sut = DefaultsAddKeyForm(existingKeys: nil, cancel: {}, add: { added.append("\($0)|\($1.title)") })
            var hasKeyField = true

            try await ViewHosting.host(sut) {
                try await sut.inspection.inspect { view in
                    hasKeyField = (try? view.find(ViewType.TextField.self)) != nil
                    try view.find(ViewType.Picker.self).select(value: PropertyListType.number)
                }
                try await sut.inspection.inspect { view in
                    try view.find(button: "Add").tap()
                }
            }

            #expect(!hasKeyField)
            #expect(added == ["|Number"])
        }

        @Test("Data that isn't hex says why under the field and holds Save back; fixed, Save saves the bytes")
        func dataValidation() async throws {
            var saved: [PropertyListValue] = []
            let sut = PropertyListScalarEditor(value: .data(Data([0xFF])), title: "token") { saved.append($0) }
            var isSaveDisabled = false
            var problem = ""

            try await ViewHosting.host(sut) {
                try await sut.inspection.inspect { view in
                    try view.find(ViewType.TextField.self).setInput("0g")
                }
                try await sut.inspection.inspect { view in
                    isSaveDisabled = try view.find(button: "Save").isDisabled()
                    problem = try view.find(text: "“g” isn't a hex digit (0–9, a–f).").string()
                    try view.find(ViewType.TextField.self).setInput("dead beef")
                }
                try await sut.inspection.inspect { view in
                    try view.find(button: "Save").tap()
                }
            }

            #expect(isSaveDisabled)
            #expect(problem == "“g” isn't a hex digit (0–9, a–f).")
            #expect(saved == [.data(Data([0xDE, 0xAD, 0xBE, 0xEF]))])
        }

        @Test("Switching data to Base64 shows the same bytes in Base64, and Save reads them that way")
        func dataBase64() async throws {
            var saved: [PropertyListValue] = []
            let sut = PropertyListScalarEditor(value: .data(Data([0xDE, 0xAD, 0xBE, 0xEF])), title: "token") { saved.append($0) }
            var text = ""

            try await ViewHosting.host(sut) {
                try await sut.inspection.inspect { view in
                    try view.find(ViewType.Picker.self).select(value: DataTextEncoding.base64)
                }
                try await sut.inspection.inspect { view in
                    text = try view.find(ViewType.TextField.self).input()
                    try view.find(button: "Save").tap()
                }
            }

            #expect(text == "3q2+7w==")
            #expect(saved == [.data(Data([0xDE, 0xAD, 0xBE, 0xEF]))])
        }

        @Test("A real that isn't a number says why and holds Save back")
        func numberValidation() async throws {
            let sut = PropertyListScalarEditor(value: .number(NSNumber(value: 2.5)), title: "volume") { _ in }
            var isSaveDisabled = false
            var problem = ""

            try await ViewHosting.host(sut) {
                try await sut.inspection.inspect { view in
                    try view.find(ViewType.TextField.self).setInput("three")
                }
                try await sut.inspection.inspect { view in
                    isSaveDisabled = try view.find(button: "Save").isDisabled()
                    problem = try view.find(text: PropertyListTextError.notNumber.message).string()
                }
            }

            #expect(isSaveDisabled)
            #expect(problem == PropertyListTextError.notNumber.message)
        }

        @Test("An integer given a fraction says it needs a whole number, keeps the field and holds Save back")
        func integerValidation() async throws {
            var saved: [PropertyListValue] = []
            let sut = PropertyListScalarEditor(value: .number(NSNumber(value: 3)), title: "launchCount") { saved.append($0) }
            let expected = PropertyListTextError.notInteger.message
            var isSaveDisabled = false
            var problem = ""
            var fieldText = ""

            try await ViewHosting.host(sut) {
                try await sut.inspection.inspect { view in
                    try view.find(ViewType.TextField.self).setInput("3.5")
                }
                try await sut.inspection.inspect { view in
                    // A disabled button refuses the tap, so nothing is saved either way.
                    try? view.find(button: "Save").tap()
                }
                try await sut.inspection.inspect { view in
                    isSaveDisabled = try view.find(button: "Save").isDisabled()
                    problem = try view.find(text: expected).string()
                    fieldText = try view.find(ViewType.TextField.self).input()
                }
            }

            #expect(isSaveDisabled)
            #expect(problem == expected)
            #expect(fieldText == "3.5")
            #expect(saved.isEmpty)
        }

        @Test("Saving an integer's field saves an integer, and a real's a real, though both read 4")
        func numberSavesKeepKind() async throws {
            var saved: [PropertyListValue] = []
            let integer = PropertyListScalarEditor(value: .number(NSNumber(value: 3)), title: "launchCount") { saved.append($0) }
            let real = PropertyListScalarEditor(value: .number(NSNumber(value: 2.5)), title: "volume") { saved.append($0) }

            for sut in [integer, real] {
                try await ViewHosting.host(sut) {
                    try await sut.inspection.inspect { view in
                        try view.find(ViewType.TextField.self).setInput("4")
                    }
                    try await sut.inspection.inspect { view in
                        try view.find(button: "Save").tap()
                    }
                }
            }

            let kinds = saved.map { value -> String in
                guard case let .number(number) = value else { return "not a number" }
                return String(cString: number.objCType)
            }
            #expect(saved == [.number(4), .number(4)])
            #expect(kinds == ["q", "d"])
        }

        @Test("A key from another domain names it, shows why it is read-only, and offers no editor or Delete Key")
        func readOnlyRow() throws {
            let entry = DefaultsEntry(key: "AppleLanguages", value: .array([.string("en")]), domain: .global)
            let sut = DefaultsEntryRow(entry: entry, redaction: .standard, isSelected: true, onSelect: {}, onSet: { _ in }, onDelete: {})
            let expectedReason = DefaultsDomain.global.readOnlyReason ?? ""

            let view = try sut.inspect()

            #expect(throws: Never.self) { try view.find(text: "Array · Global") }
            #expect(throws: Never.self) { try view.find(text: expectedReason) }
            #expect(throws: Never.self) { try view.find(button: "Copy Value") }
            #expect((try? view.find(button: "Delete Key")) == nil)
            #expect((try? view.find(PropertyListEditor.self)) == nil)
        }

        @Test("A key of the persistent domain names only its type and offers Delete Key")
        func persistentRow() throws {
            let entry = DefaultsEntry(key: "launchCount", value: .number(3))
            let sut = DefaultsEntryRow(entry: entry, redaction: .standard, isSelected: true, onSelect: {}, onSet: { _ in }, onDelete: {})

            let view = try sut.inspect()

            #expect(throws: Never.self) { try view.find(text: "Number") }
            #expect(throws: Never.self) { try view.find(button: "Delete Key") }
            #expect(throws: Never.self) { try view.find(PropertyListEditor.self) }
        }

        @Test("Picking false for a Boolean saves it at once")
        func booleanSaves() throws {
            var saved: [PropertyListValue] = []
            let sut = PropertyListScalarEditor(value: .bool(true), title: "sync") { saved.append($0) }

            try sut.inspect().find(ViewType.Picker.self).select(value: false)

            #expect(saved == [.bool(false)])
        }

        @Test("Drilling into a nested dictionary and saving a value there saves the key's whole value with only that changed")
        func editNestedDictionary() async throws {
            var saved: [PropertyListValue] = []
            let value = PropertyListValue.dictionary([
                "theme": .dictionary(["accent": .string("orange"), "contrast": .number(1.5)]),
                "sync": .bool(true)
            ])
            let expected = PropertyListValue.dictionary([
                "theme": .dictionary(["accent": .string("teal"), "contrast": .number(1.5)]),
                "sync": .bool(true)
            ])
            let sut = PropertyListEditor(key: "settings", value: value) { saved.append($0) }
            var trail = ""

            try await ViewHosting.host(sut) {
                try await sut.inspection.inspect { view in
                    try view.find(ViewType.Button.self, where: { try $0.accessibilityLabel().string() == "theme, Dictionary, 2 keys" }).tap()
                }
                try await sut.inspection.inspect { view in
                    try view.find(ViewType.Button.self, where: { try $0.accessibilityLabel().string() == "accent, String, orange" }).tap()
                }
                try await sut.inspection.inspect { view in
                    trail = try view.find(text: "settings › theme › accent").string()
                    try view.find(PropertyListScalarEditor.self).actualView().save(.string("teal"))
                }
            }

            #expect(trail == "settings › theme › accent")
            #expect(saved == [expected])
        }

        @Test("Drilling into an array's element and saving it saves the whole array with that element changed")
        func editArrayElement() async throws {
            var saved: [PropertyListValue] = []
            let value = PropertyListValue.array([.string("recent"), .string("favorites")])
            let expected = PropertyListValue.array([.string("recent"), .string("starred")])
            let sut = PropertyListEditor(key: "tabs", value: value) { saved.append($0) }

            try await ViewHosting.host(sut) {
                try await sut.inspection.inspect { view in
                    try view.find(ViewType.Button.self, where: { try $0.accessibilityLabel().string() == "[1], String, favorites" }).tap()
                }
                try await sut.inspection.inspect { view in
                    try view.find(PropertyListScalarEditor.self).actualView().save(.string("starred"))
                }
            }

            #expect(saved == [expected])
        }

        @Test("A value inside a container names its field by its path and keeps Save and Delete Item on one row")
        func nestedValueActions() async throws {
            let sut = PropertyListScalarEditor(value: .string("orange"), title: "settings › theme › accent", deleteItem: {}, save: { _ in })
            var fieldTitle = ""
            var hasNewValue = true
            var isOneRow = false

            try await ViewHosting.host(sut) {
                try await sut.inspection.inspect { view in
                    fieldTitle = try view.find(text: "settings › theme › accent").string()
                    hasNewValue = (try? view.find(text: "New value")) != nil
                    isOneRow = (try? view.find(ViewType.HStack.self, where: { row in
                        (try? row.find(button: "Save")) != nil && (try? row.find(button: "Delete Item")) != nil
                    })) != nil
                }
            }

            #expect(fieldTitle == "settings › theme › accent")
            #expect(!hasNewValue)
            #expect(isOneRow)
        }

        @Test("A key's own value is a New value field with Save and no Delete Item")
        func topLevelValueActions() async throws {
            let sut = PropertyListScalarEditor(value: .string("ada"), title: "username") { _ in }
            var hasNewValue = false
            var hasDeleteItem = true

            try await ViewHosting.host(sut) {
                try await sut.inspection.inspect { view in
                    hasNewValue = (try? view.find(text: "New value")) != nil
                    hasDeleteItem = (try? view.find(button: "Delete Item")) != nil
                }
            }

            #expect(hasNewValue)
            #expect(!hasDeleteItem)
        }

        @Test("A selected key's delete reads Delete Key, apart from a nested value's Delete Item")
        func deleteKeyLabel() throws {
            let entry = DefaultsEntry(key: "settings", value: .dictionary(["sync": .bool(true)]))
            let sut = DefaultsEntryRow(entry: entry, redaction: .standard, isSelected: true, onSelect: {}, onSet: { _ in }, onDelete: {})
            let expected = "Delete Key settings"

            let actual = try sut.inspect().find(button: "Delete Key").accessibilityLabel().string()

            #expect(actual == expected)
        }

        @Test("Delete Item removes the element drilled into from the whole value")
        func deleteItem() async throws {
            var saved: [PropertyListValue] = []
            let value = PropertyListValue.array([.string("recent"), .string("favorites")])
            let expected = PropertyListValue.array([.string("favorites")])
            let sut = PropertyListEditor(key: "tabs", value: value) { saved.append($0) }

            try await ViewHosting.host(sut) {
                try await sut.inspection.inspect { view in
                    try view.find(ViewType.Button.self, where: { try $0.accessibilityLabel().string() == "[0], String, recent" }).tap()
                }
                try await sut.inspection.inspect { view in
                    try view.find(button: "Delete Item").tap()
                }
            }

            #expect(saved == [expected])
        }

        @Test("Add Item in an array appends an item of the type picked to the whole value")
        func addArrayItem() async throws {
            var saved: [PropertyListValue] = []
            let value = PropertyListValue.array([.string("recent")])
            let expected = PropertyListValue.array([.string("recent"), .number(0)])
            let sut = PropertyListEditor(key: "tabs", value: value) { saved.append($0) }

            try await ViewHosting.host(sut) {
                try await sut.inspection.inspect { view in
                    try view.find(button: "Add Item").tap()
                }
                try await sut.inspection.inspect { view in
                    try view.find(DefaultsAddKeyForm.self).actualView().add("", .number)
                }
            }

            #expect(saved == [expected])
        }
    }
#endif
