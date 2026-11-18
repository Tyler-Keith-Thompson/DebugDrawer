// ViewInspector is linked on Apple platforms only, and the views are tested on the Mac.
#if os(macOS)
    @testable import DebugDrawer
    import Foundation
    import SwiftUI
    import Testing
    import ViewInspector

    private struct ChattyPlugin: DebugDrawerPlugin {
        var title = "Chatty"
        var icon = "bell"
        var body: some View { Text("Chatty body") }
    }

    // Each test makes a drawer of its own over a UserDefaults suite of its own, removed when the
    // test ends, so the mute state it saves reaches no other test and not the shared drawer.
    @MainActor
    @Suite("Silencing notices from a section header")
    struct NoticeMutingViewTests {
        @Test("A global plugin's section header menu silences its notices with Silence Notices")
        func contextMenuSilences() throws {
            let name = "NoticeMutingViewTests.\(UUID().uuidString)"
            let suite = try #require(UserDefaults(suiteName: name))
            defer { suite.removePersistentDomain(forName: name) }
            let drawer = DebugDrawer(defaults: suite)
            drawer.registerGlobal(ChattyPlugin())
            let presentation = DrawerPresentation()
            presentation.isOpen = true
            let overlay = DebugDrawerOverlay(drawer: drawer, presentation: presentation)
            // ViewInspector can't open a context menu, so the test inspects the menu the header's
            // `contextMenu` shows.
            let sut = overlay.pluginMenu(AnyDebugDrawerPlugin(ChattyPlugin()), isGlobal: true, pinned: false)

            try sut.inspect().find(button: "Silence Notices").tap()

            #expect(drawer.isNoticesMuted(forPlugin: "ChattyPlugin"))
        }

        @Test("A silenced local plugin's section header menu offers Allow Notices, not Silence Notices, which allows them again")
        func contextMenuAllows() throws {
            let name = "NoticeMutingViewTests.\(UUID().uuidString)"
            let suite = try #require(UserDefaults(suiteName: name))
            defer { suite.removePersistentDomain(forName: name) }
            let drawer = DebugDrawer(defaults: suite)
            drawer.registerGlobal(ChattyPlugin())
            drawer.setNoticesMuted(true, forPlugin: "ChattyPlugin")
            let presentation = DrawerPresentation()
            presentation.isOpen = true
            let overlay = DebugDrawerOverlay(drawer: drawer, presentation: presentation)
            let sut = overlay.pluginMenu(AnyDebugDrawerPlugin(ChattyPlugin()), isGlobal: false, pinned: false)

            let silence = try sut.inspect().findAll(ViewType.Button.self) { try $0.labelView().text().string() == "Silence Notices" }
            try sut.inspect().find(button: "Allow Notices").tap()

            #expect(silence.isEmpty)
            #expect(!drawer.isNoticesMuted(forPlugin: "ChattyPlugin"))
        }

        @Test("A silenced plugin's section header shows a crossed-out bell and reads Notices silenced")
        func silencedHeaderShowsTheBell() throws {
            let plugin = AnyDebugDrawerPlugin(ChattyPlugin())
            let sut = PluginSectionHeader(plugin: plugin, isExpanded: false, isPinned: false, badge: nil, isMovable: true, isNoticesMuted: true) {}

            let bell = try sut.inspect().find(ViewType.Image.self) { try $0.actualImage().name() == "bell.slash" }
            let value = try sut.inspect().find(ViewType.Button.self).accessibilityValue().string()

            #expect(try bell.accessibilityLabel().string() == "Notices silenced")
            #expect(value == "Collapsed, Notices silenced")
        }

        @Test("An allowed plugin's section header shows no crossed-out bell")
        func allowedHeaderHasNoBell() throws {
            let plugin = AnyDebugDrawerPlugin(ChattyPlugin())
            let sut = PluginSectionHeader(plugin: plugin, isExpanded: false, isPinned: false, badge: nil, isMovable: true) {}

            let actual = try sut.inspect().findAll(ViewType.Image.self) { try $0.actualImage().name() == "bell.slash" }

            #expect(actual.isEmpty)
        }
    }
#endif
