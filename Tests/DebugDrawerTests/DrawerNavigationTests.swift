// ViewInspector is linked on Apple platforms only, and the views are tested on the Mac.
#if os(macOS)
    @testable import DebugDrawer
    import SwiftUI
    import Testing
    import ViewInspector

    private struct NavigationFixture: DebugDrawerPlugin {
        var title: String
        var icon = "shippingbox"
        var body: some View {
            Text("\(title) body")
        }
    }

    // Serialized: these tests register plugins with the one shared drawer.
    @MainActor
    @Suite("Drawer navigation", .serialized)
    struct DrawerNavigationTests {
        @Test("A section header's Show Alone button shows that plugin alone")
        func showAloneButtonFocusesThePlugin() throws {
            let plugin = NavigationFixture(title: "Navigation Orders")
            DebugDrawer.shared.registerGlobal(plugin)
            defer { DebugDrawer.shared.unregisterGlobal(id: plugin.id) }
            let presentation = DrawerPresentation()
            presentation.isOpen = true
            let sut = DebugDrawerOverlay(drawer: .shared, presentation: presentation)
            let expected = DrawerNavigation.plugin(plugin.id)

            try sut.inspect().find(ViewType.Button.self) {
                try $0.accessibilityLabel().string() == "Show Navigation Orders alone"
            }.tap()

            #expect(presentation.navigation == expected)
        }

        @Test("A plugin shown alone fills the panel: its detail view, under a jump bar that ends at it, with no outline")
        func pluginShownAloneHasTheDetailView() throws {
            let plugin = NavigationFixture(title: "Navigation Detail")
            let other = NavigationFixture(title: "Navigation Other")
            DebugDrawer.shared.registerGlobal(plugin)
            DebugDrawer.shared.registerGlobal(other)
            defer {
                DebugDrawer.shared.unregisterGlobal(id: plugin.id)
                DebugDrawer.shared.unregisterGlobal(id: other.id)
            }
            let presentation = DrawerPresentation()
            presentation.isOpen = true
            presentation.navigation = .plugin(plugin.id)
            let sut = DebugDrawerOverlay(drawer: .shared, presentation: presentation)

            let detail = try sut.inspect().find(DrawerPluginDetail.self)
            let jumpBar = try sut.inspect().find(DrawerJumpBar.self)
            let texts = try sut.inspect().findAll(ViewType.Text.self).compactMap { try? $0.string() }
            let tabs = try sut.inspect().findAll(DrawerNavigatorTabs.self)

            #expect(try detail.actualView().plugin.id == plugin.id)
            #expect(try jumpBar.actualView().focus?.id == plugin.id)
            #expect(texts.contains("Navigation Detail body"))
            #expect(!texts.contains("Navigation Other body"))
            #expect(tabs.isEmpty)
        }

        @Test("The back button returns from a plugin shown alone to the outline")
        func backReturnsToTheOutline() throws {
            let plugin = NavigationFixture(title: "Navigation Back")
            DebugDrawer.shared.registerGlobal(plugin)
            defer { DebugDrawer.shared.unregisterGlobal(id: plugin.id) }
            let presentation = DrawerPresentation()
            presentation.isOpen = true
            presentation.navigation = .plugin(plugin.id)
            let sut = DebugDrawerOverlay(drawer: .shared, presentation: presentation)

            try sut.inspect().find(ViewType.Button.self) {
                try $0.accessibilityLabel().string() == "Back to all plugins"
            }.tap()

            #expect(presentation.navigation == .outline)
        }

        @Test("In the outline there is no back button")
        func outlineHasNoBackButton() throws {
            let presentation = DrawerPresentation()
            presentation.isOpen = true
            let sut = DebugDrawerOverlay(drawer: .shared, presentation: presentation)

            let actual = try sut.inspect().findAll(ViewType.Button.self) {
                try $0.accessibilityLabel().string() == "Back to all plugins"
            }

            #expect(actual.isEmpty)
        }

        @Test("The jump bar's menu shows a plugin alone, and All Plugins returns to the outline")
        func jumpBarMenuNavigates() throws {
            let plugin = NavigationFixture(title: "Navigation Menu")
            DebugDrawer.shared.registerGlobal(plugin)
            defer { DebugDrawer.shared.unregisterGlobal(id: plugin.id) }
            let presentation = DrawerPresentation()
            presentation.isOpen = true
            let sut = DebugDrawerOverlay(drawer: .shared, presentation: presentation)

            let menu = try sut.inspect().find(ViewType.Menu.self)
            try menu.find(button: "Navigation Menu").tap()
            let shown = presentation.navigation
            try menu.find(button: "All Plugins").tap()

            #expect(shown == .plugin(plugin.id))
            #expect(presentation.navigation == .outline)
        }

        @Test("In the compact panel a plugin's header shows it alone instead of expanding it, and no body opens under it")
        func compactHeaderShowsThePluginAlone() throws {
            let plugin = NavigationFixture(title: "Navigation Compact")
            DebugDrawer.shared.registerGlobal(plugin)
            defer { DebugDrawer.shared.unregisterGlobal(id: plugin.id) }
            let presentation = DrawerPresentation()
            presentation.isOpen = true
            presentation.layout = .compact
            let sut = DebugDrawerOverlay(drawer: .shared, presentation: presentation)
            let texts = try sut.inspect().findAll(ViewType.Text.self).compactMap { try? $0.string() }
            let showAloneButtons = try sut.inspect().findAll(ViewType.Button.self) {
                try $0.accessibilityLabel().string() == "Show Navigation Compact alone"
            }

            try sut.inspect().find(ViewType.Button.self) {
                try $0.accessibilityLabel().string() == "Navigation Compact"
            }.tap()

            #expect(!texts.contains("Navigation Compact body"))
            #expect(showAloneButtons.isEmpty)
            #expect(presentation.navigation == .plugin(plugin.id))
        }

        @Test("Escape in a plugin shown alone returns to the outline and leaves the drawer open")
        func escapeLeavesThePluginFirst() throws {
            let plugin = NavigationFixture(title: "Navigation Escape")
            DebugDrawer.shared.registerGlobal(plugin)
            defer { DebugDrawer.shared.unregisterGlobal(id: plugin.id) }
            let presentation = DrawerPresentation()
            presentation.isOpen = true
            presentation.navigation = .plugin(plugin.id)
            let sut = DebugDrawerOverlay(drawer: .shared, presentation: presentation)

            // The shortcut buttons are hidden, which ViewInspector won't tap; Escape runs `close`.
            try sut.inspect().find(DrawerKeyboardShortcuts.self).actualView().close()

            #expect(presentation.navigation == .outline)
            #expect(presentation.isOpen)
        }

        @Test("A plugin that is no longer registered leaves the panel in the outline")
        func unregisteredPluginShowsTheOutline() throws {
            let presentation = DrawerPresentation()
            presentation.isOpen = true
            presentation.navigation = .plugin("NoSuchPlugin")
            let sut = DebugDrawerOverlay(drawer: .shared, presentation: presentation)

            let actual = try sut.inspect().findAll(DrawerPluginDetail.self)

            #expect(actual.isEmpty)
        }
    }

#endif
