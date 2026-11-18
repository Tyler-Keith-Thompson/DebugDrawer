// Views render on the Mac; ViewInspector is linked on Apple platforms only.
#if os(macOS)
    @testable import DebugDrawer
    import SwiftUI
    import Testing
    import ViewInspector

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct EmptyStateTests {
        @Test("An empty state shows its title and description, and hides its symbol from VoiceOver")
        func titleAndDescription() throws {
            let sut = DebugDrawerEmptyState("No files yet", systemImage: "folder") {
                Text("Files the app writes show here.")
            }

            let view = try sut.inspect()

            #expect(try view.find(text: "No files yet").string() == "No files yet")
            #expect(try view.find(text: "Files the app writes show here.").string() == "Files the app writes show here.")
            #expect(try view.find(ViewType.Image.self).accessibilityHidden())
        }

        @Test("The drawer with no plugins shows its own empty state")
        func drawerEmptyState() throws {
            let sut = DrawerEmptyState()

            let actual = try sut.inspect().find(DebugDrawerEmptyState<EmptyView>.self).actualView().title

            #expect(actual == "No plugins registered")
        }
    }
#endif
