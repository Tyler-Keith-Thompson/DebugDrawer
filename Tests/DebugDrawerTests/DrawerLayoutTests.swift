#if DEBUG
    @testable import DebugDrawer
    import Foundation
    import SwiftUI
    import Testing

    struct LayoutConsole: DebugDrawerPlugin {
        var title = "Console"
        var icon = "terminal"
        var category = "Logs"
        var body: some View { EmptyView() }
    }

    struct LayoutNetwork: DebugDrawerPlugin {
        var title = "Network"
        var icon = "network"
        var category = "Logs"
        var body: some View { EmptyView() }
    }

    struct LayoutKeychain: DebugDrawerPlugin {
        var title = "Keychain"
        var icon = "key"
        var category = "Storage"
        var body: some View { EmptyView() }
    }

    struct LayoutUncategorized: DebugDrawerPlugin {
        var title = "Custom"
        var icon = "gear"
        var body: some View { EmptyView() }
    }

    @MainActor
    @Suite("Drawer layout")
    struct DrawerLayoutTests {
        @Test("Global plugins are grouped by category, alphabetically, with General last")
        func pluginsAreGroupedByCategory() {
            let plugins = [
                AnyDebugDrawerPlugin(LayoutUncategorized()),
                AnyDebugDrawerPlugin(LayoutKeychain()),
                AnyDebugDrawerPlugin(LayoutConsole()),
                AnyDebugDrawerPlugin(LayoutNetwork())
            ]
            let expected = ["Logs: Console, Network", "Storage: Keychain", "General: Custom"]

            let actual = DrawerLayout().sections(for: plugins)
                .map { "\($0.title): " + $0.plugins.map(\.title).joined(separator: ", ") }

            #expect(actual == expected)
        }

        @Test("A plugin that declares no category is in General")
        func aPluginWithoutACategoryIsGeneral() {
            let sut = AnyDebugDrawerPlugin(LayoutUncategorized())

            #expect(sut.category == "General")
        }

        @Test("Pinned plugins come first, in the order they were pinned, and leave their category")
        func pinnedPluginsComeFirst() {
            let plugins = [
                AnyDebugDrawerPlugin(LayoutConsole()),
                AnyDebugDrawerPlugin(LayoutNetwork()),
                AnyDebugDrawerPlugin(LayoutKeychain())
            ]
            var sut = DrawerLayout()
            let expected = ["Pinned: Keychain, Network", "Logs: Console"]

            sut.togglePin("DebugDrawerTests.LayoutKeychain")
            sut.togglePin("DebugDrawerTests.LayoutNetwork")

            let actual = sut.sections(for: plugins)
                .map { "\($0.title): " + $0.plugins.map(\.title).joined(separator: ", ") }
            #expect(actual == expected)
        }

        @Test("Pinning twice unpins")
        func pinningTwiceUnpins() {
            var sut = DrawerLayout()

            sut.togglePin("DebugDrawerTests.LayoutConsole")
            sut.togglePin("DebugDrawerTests.LayoutConsole")

            #expect(sut.pinned.isEmpty)
        }

        @Test("Moving a plugin down reorders it within its category")
        func movingAPluginDownReordersIt() {
            let plugins = [
                AnyDebugDrawerPlugin(LayoutConsole()),
                AnyDebugDrawerPlugin(LayoutNetwork()),
                AnyDebugDrawerPlugin(LayoutKeychain())
            ]
            var sut = DrawerLayout()
            let expected = ["Network", "Console"]

            sut.move("DebugDrawerTests.LayoutConsole", by: 1, among: plugins)

            let actual = sut.sections(for: plugins).first?.plugins.map(\.title)
            #expect(actual == expected)
        }

        @Test("Moving past either end of a group changes nothing")
        func movingPastTheEndsChangesNothing() {
            let plugins = [AnyDebugDrawerPlugin(LayoutConsole()), AnyDebugDrawerPlugin(LayoutNetwork())]
            var sut = DrawerLayout()
            let expected = DrawerLayout()

            sut.move("DebugDrawerTests.LayoutConsole", by: -1, among: plugins)
            sut.move("DebugDrawerTests.LayoutNetwork", by: 1, among: plugins)

            #expect(sut == expected)
        }

        @Test("Moving a pinned plugin reorders the pins")
        func movingAPinnedPluginReordersThePins() {
            let plugins = [AnyDebugDrawerPlugin(LayoutConsole()), AnyDebugDrawerPlugin(LayoutKeychain())]
            var sut = DrawerLayout()
            sut.togglePin("DebugDrawerTests.LayoutConsole")
            sut.togglePin("DebugDrawerTests.LayoutKeychain")
            let expected = ["DebugDrawerTests.LayoutKeychain", "DebugDrawerTests.LayoutConsole"]

            sut.move("DebugDrawerTests.LayoutKeychain", by: -1, among: plugins)

            #expect(sut.pinned == expected)
        }

        @Test("Pins, order and the last-used plugin survive a relaunch through UserDefaults")
        func theLayoutSurvivesARelaunch() throws {
            let suite = "DrawerLayoutTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let plugins = [
                AnyDebugDrawerPlugin(LayoutConsole()),
                AnyDebugDrawerPlugin(LayoutNetwork()),
                AnyDebugDrawerPlugin(LayoutKeychain())
            ]
            var expected = DrawerLayout()
            expected.togglePin("DebugDrawerTests.LayoutKeychain")
            expected.move("DebugDrawerTests.LayoutNetwork", by: -1, among: plugins)
            expected.lastUsed = "DebugDrawerTests.LayoutNetwork"

            expected.save(to: defaults)
            let actual = DrawerLayout(from: try #require(UserDefaults(suiteName: suite)))

            #expect(actual == expected)
            #expect(actual.sections(for: plugins).map { $0.plugins.map(\.title) } == [["Keychain"], ["Network", "Console"]])
        }

        @Test("Nothing stored, or data that can't be read, gives an empty layout")
        func unreadableStorageGivesAnEmptyLayout() throws {
            let suite = "DrawerLayoutTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let expected = DrawerLayout()

            let nothingStored = DrawerLayout(from: defaults)
            defaults.set(Data("not json".utf8), forKey: DrawerLayout.defaultsKey)
            let garbage = DrawerLayout(from: defaults)

            #expect(nothingStored == expected)
            #expect(garbage == expected)
        }

        @Test("Stored IDs of plugins no longer registered are skipped")
        func staleIDsAreSkipped() {
            var sut = DrawerLayout()
            sut.togglePin("RemovedPlugin")
            sut.order = ["RemovedPlugin", "DebugDrawerTests.LayoutConsole"]
            let expected = [["Console"]]

            let actual = sut.sections(for: [AnyDebugDrawerPlugin(LayoutConsole())]).map { $0.plugins.map(\.title) }

            #expect(actual == expected)
        }

        @Test("No plugins give no groups")
        func noPluginsGiveNoGroups() {
            let actual = DrawerLayout().sections(for: [])

            #expect(actual.isEmpty)
        }

        @Test("Local plugins come first, in their order, under Local, then the pinned and categorized global ones")
        func localPluginsComeFirst() {
            let local = [AnyDebugDrawerPlugin(LayoutUncategorized()), AnyDebugDrawerPlugin(LayoutKeychain())]
            let global = [AnyDebugDrawerPlugin(LayoutConsole()), AnyDebugDrawerPlugin(LayoutNetwork())]
            var sut = DrawerLayout()
            sut.togglePin("DebugDrawerTests.LayoutNetwork")
            let expected = ["local Local: Custom, Keychain", "pinned Pinned: Network", "category:Logs Logs: Console"]

            let actual = sut.sections(local: local, global: global)
                .map { "\($0.id) \($0.title): " + $0.plugins.map(\.title).joined(separator: ", ") }

            #expect(actual == expected)
        }

        @Test("Without local plugins the list has no Local group, only the global ones'")
        func noLocalPluginsGiveNoLocalGroup() {
            let global = [AnyDebugDrawerPlugin(LayoutConsole()), AnyDebugDrawerPlugin(LayoutKeychain())]
            let sut = DrawerLayout()
            let expected = sut.sections(for: global).map(\.id)

            let actual = sut.sections(local: [], global: global).map(\.id)

            #expect(actual == expected)
        }

        @Test("Local plugins alone give one Local group")
        func localPluginsAloneGiveOneGroup() {
            let local = [AnyDebugDrawerPlugin(LayoutConsole())]
            let expected: [DrawerSection.Kind] = [.local]

            let actual = DrawerLayout().sections(local: local, global: []).map(\.kind)

            #expect(actual == expected)
        }

        @Test("A category titled Local or Pinned keeps an ID apart from the Local and Pinned groups")
        func categoryIDsStayApartFromLocalAndPinned() {
            struct LocalCategory: DebugDrawerPlugin {
                var title = "Local Tool"
                var icon = "gear"
                var category = "Local"
                var body: some View { EmptyView() }
            }
            struct PinnedCategory: DebugDrawerPlugin {
                var title = "Pinned Tool"
                var icon = "gear"
                var category = "Pinned"
                var body: some View { EmptyView() }
            }
            var sut = DrawerLayout()
            sut.togglePin("DebugDrawerTests.LayoutConsole")
            let local = [AnyDebugDrawerPlugin(LayoutKeychain())]
            let global = [AnyDebugDrawerPlugin(LayoutConsole()), AnyDebugDrawerPlugin(LocalCategory()), AnyDebugDrawerPlugin(PinnedCategory())]
            let expected = ["local", "pinned", "category:Local", "category:Pinned"]

            let actual = sut.sections(local: local, global: global).map(\.id)

            #expect(actual == expected)
        }

        @Test("No plugins at all give no groups")
        func noLocalOrGlobalPluginsGiveNoGroups() {
            let actual = DrawerLayout().sections(local: [], global: [])

            #expect(actual.isEmpty)
        }
    }
#endif
