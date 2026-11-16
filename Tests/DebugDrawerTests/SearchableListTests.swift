// Views render on the Mac; ViewInspector is linked on Apple platforms only.
#if os(macOS)
    @testable import DebugDrawer
    import SwiftUI
    import Testing
    import ViewInspector

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct SearchableListTests {
        @Test("The list shows its rows below a field labelled for VoiceOver")
        func rows() throws {
            let sut = DebugDrawerSearchableList("Filter...", text: .constant(""), accessibilityLabel: "Filter keys and values") {
                ForEach(["apiBaseURL", "hasOnboarded"], id: \.self) { key in
                    Text(key)
                }
            }
            let expectedRows = ["apiBaseURL", "hasOnboarded"]
            let expectedLabel = "Filter keys and values"

            let actualRows = try sut.inspect().find(ViewType.LazyVStack.self).findAll(ViewType.Text.self).map { try $0.string() }
            let actualLabel = try sut.inspect().find(ViewType.TextField.self).accessibilityLabel().string()

            #expect(actualRows == expectedRows)
            #expect(actualLabel == expectedLabel)
        }

        @Test("Typing in the field sets the filter text")
        func typing() throws {
            var filter = ""
            let text = Binding(get: { filter }, set: { filter = $0 })
            let sut = DebugDrawerSearchableList("Filter...", text: text, accessibilityLabel: "Filter requests") {
                Text("GET /orders")
            }
            let expected = "orders"

            try sut.inspect().find(ViewType.TextField.self).setInput(expected)

            #expect(filter == expected)
        }

        @Test("With no rows the list is empty, and the field is still there")
        func noRows() throws {
            let sut = DebugDrawerSearchableList("Filter...", text: .constant("zzz"), accessibilityLabel: "Filter requests") {
                ForEach([String](), id: \.self) { Text($0) }
            }

            let rows = try sut.inspect().find(ViewType.LazyVStack.self).findAll(ViewType.Text.self)
            let field = try sut.inspect().find(ViewType.TextField.self)

            #expect(rows.isEmpty)
            #expect(try field.input() == "zzz")
        }
    }
#endif
