// ViewInspector is linked on Apple platforms only, and the views are tested on the Mac.
#if os(macOS)
    @testable import DebugDrawer
    @testable import DebugDrawerViewInspectorPlugin
    import SwiftUI
    import Testing
    import ViewInspector

    @MainActor
    @Suite
    struct RenderCountListTests {
        @Test("Each tracked name is listed with its count, in the order given, under a total of views and renders")
        func listsEntriesInOrder() throws {
            let entries = [
                RenderTracker.Entry(id: "FeedView", count: 24),
                RenderTracker.Entry(id: "AvatarView", count: 7),
                RenderTracker.Entry(id: "SettingsView", count: 1)
            ]
            let sut = RenderCountList(entries: entries) {}
            let expected = [
                "3 views, 32 renders", "Reset",
                "FeedView — 24 renders", "AvatarView — 7 renders", "SettingsView — 1 render"
            ]

            let actual = try sut.inspect().findAll(ViewType.Text.self).map { try $0.string() }

            #expect(actual == expected)
        }

        @Test("With nothing tracked, the list says how to track a view and offers no Reset")
        func emptyList() throws {
            let sut = RenderCountList(entries: []) {}
            let expected = ["No tracked views", "Add .trackRenders(\"Name\") to a view's body to count its renders."]

            let actual = try sut.inspect().findAll(ViewType.Text.self).map { try $0.string() }

            #expect(actual == expected)
        }

        @Test("One view with one render is counted in the singular")
        func singular() throws {
            let sut = RenderCountList(entries: [RenderTracker.Entry(id: "FeedView", count: 1)]) {}
            let expected = "1 view, 1 render"

            let actual = try sut.inspect().findAll(ViewType.Text.self).first?.string()

            #expect(actual == expected)
        }

        @Test("Reset calls back once")
        func resetCallsBack() throws {
            var resets = 0
            let sut = RenderCountList(entries: [RenderTracker.Entry(id: "FeedView", count: 2)]) { resets += 1 }

            try sut.inspect().find(button: "Reset").tap()

            #expect(resets == 1)
        }
    }
#endif
