#if DEBUG
    @testable import DebugDrawer
    import SwiftUI
    import Testing
    import ViewInspector

    struct SearchFixture: DebugDrawerPlugin {
        var title: String
        var icon = "gear"
        var actions: [DebugDrawerAction] = []
        var body: some View { EmptyView() }
    }

    @MainActor
    @Suite("Drawer search")
    struct DrawerSearchTests {
        @Test("Part of a plugin's title finds the plugin")
        func partOfATitleFindsThePlugin() {
            let plugins = [
                AnyDebugDrawerPlugin(SearchFixture(title: "Console")),
                AnyDebugDrawerPlugin(SearchFixture(title: "Network"))
            ]
            let expected = ["Network"]

            let actual = DrawerSearchResult.matches("etw", in: plugins).map(\.title)

            #expect(actual == expected)
        }

        @Test("Matching ignores case and diacritics")
        func matchingIgnoresCaseAndDiacritics() {
            let plugins = [AnyDebugDrawerPlugin(SearchFixture(title: "Café Menu"))]
            let expected = ["Café Menu"]

            let actual = DrawerSearchResult.matches("CAFE", in: plugins).map(\.title)

            #expect(actual == expected)
        }

        @Test("A title that starts with the query ranks before one that only contains it")
        func aPrefixRanksBeforeAContainingTitle() {
            let plugins = [
                AnyDebugDrawerPlugin(SearchFixture(title: "Internet")),
                AnyDebugDrawerPlugin(SearchFixture(title: "Network"))
            ]
            let expected = ["Network", "Internet"]

            let actual = DrawerSearchResult.matches("net", in: plugins).map(\.title)

            #expect(actual == expected)
        }

        @Test("An action is found by its title or a keyword, and keyword matches rank last")
        func anActionIsFoundByTitleOrKeyword() {
            let plugins = [
                AnyDebugDrawerPlugin(SearchFixture(title: "Session",
                    actions: [DebugDrawerAction("Expire token", keywords: ["logout"]) {}]
                )),
                AnyDebugDrawerPlugin(SearchFixture(title: "Cookies",
                    actions: [DebugDrawerAction("Log out of every site") {}]
                ))
            ]
            let expected = ["Log out of every site", "Expire token"]

            let actual = DrawerSearchResult.matches("log", in: plugins).map(\.title)

            #expect(actual == expected)
        }

        @Test("Ties keep registration order, with a plugin before its own actions")
        func tiesKeepRegistrationOrder() {
            let plugins = [
                AnyDebugDrawerPlugin(SearchFixture(title: "Cache",
                    actions: [DebugDrawerAction("Cache clear") {}]
                )),
                AnyDebugDrawerPlugin(SearchFixture(title: "Cached images"))
            ]
            let expected = ["Cache", "Cache clear", "Cached images"]

            let actual = DrawerSearchResult.matches("cache", in: plugins).map(\.title)

            #expect(actual == expected)
        }

        @Test("An empty or whitespace-only query matches nothing")
        func anEmptyQueryMatchesNothing() {
            let plugins = [AnyDebugDrawerPlugin(SearchFixture(title: "Console"))]

            let empty = DrawerSearchResult.matches("", in: plugins)
            let whitespace = DrawerSearchResult.matches("  \n", in: plugins)

            #expect(empty.isEmpty)
            #expect(whitespace.isEmpty)
        }

        @Test("A query nothing matches returns no results")
        func aQueryNothingMatchesReturnsNothing() {
            let plugins = [AnyDebugDrawerPlugin(SearchFixture(title: "Console"))]

            let actual = DrawerSearchResult.matches("zzz", in: plugins)

            #expect(actual.isEmpty)
        }

        @Test("No plugins give no results")
        func noPluginsGiveNoResults() {
            let actual = DrawerSearchResult.matches("console", in: [])

            #expect(actual.isEmpty)
        }

        @Test("Picking an action's result runs it")
        func pickingAnActionRunsIt() throws {
            var runs = 0
            let plugins = [AnyDebugDrawerPlugin(SearchFixture(title: "Session",
                actions: [DebugDrawerAction("Expire token") { runs += 1 }]
            ))]
            let result = try #require(DrawerSearchResult.matches("expire", in: plugins).first)
            guard case let .action(action, _) = result else {
                Issue.record("Expected an action, got \(result.title)")
                return
            }

            action.perform()

            #expect(runs == 1)
        }
    }

    // Serialized: these tests open and close the one shared drawer.
    @MainActor
    @Suite("Drawer search shortcut", .serialized)
    struct DrawerSearchShortcutTests {
        @Test("Cmd-K is not bound while the drawer is closed, so it can't open it")
        func commandKIsUnboundWhileClosed() throws {
            DebugDrawer.shared.isOpen = false
            let sut = DebugDrawerOverlay(drawer: .shared)

            let actual = try sut.inspect().findAll(ViewType.Button.self) {
                // ViewInspector can't read a shortcut; the Cmd-K button is the one with this label.
                try $0.labelView().text().string() == "Search Plugins"
            }

            #expect(actual.isEmpty)
        }

        @Test("While the drawer is open, Cmd-K is bound and the search field is shown")
        func commandKIsBoundWhileOpen() throws {
            DebugDrawer.shared.isOpen = true
            defer { DebugDrawer.shared.isOpen = false }
            let sut = DebugDrawerOverlay(drawer: .shared)

            let shortcuts = try sut.inspect().findAll(ViewType.Button.self) {
                // ViewInspector can't read a shortcut; the Cmd-K button is the one with this label.
                try $0.labelView().text().string() == "Search Plugins"
            }
            let field = try sut.inspect().find(ViewType.TextField.self)

            #expect(shortcuts.count == 1)
            #expect(try field.labelView().text().string() == "Filter")
        }
    }
#endif
