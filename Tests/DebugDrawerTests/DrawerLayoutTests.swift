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
                AnyDebugDrawerPlugin(LayoutNetwork()),
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
                AnyDebugDrawerPlugin(LayoutKeychain()),
            ]
            var sut = DrawerLayout()
            let expected = ["Pinned: Keychain, Network", "Logs: Console"]

            sut.togglePin("LayoutKeychain")
            sut.togglePin("LayoutNetwork")

            let actual = sut.sections(for: plugins)
                .map { "\($0.title): " + $0.plugins.map(\.title).joined(separator: ", ") }
            #expect(actual == expected)
        }

        @Test("Pinning twice unpins")
        func pinningTwiceUnpins() {
            var sut = DrawerLayout()

            sut.togglePin("LayoutConsole")
            sut.togglePin("LayoutConsole")

            #expect(sut.pinned.isEmpty)
        }

        @Test("Moving a plugin down reorders it within its category")
        func movingAPluginDownReordersIt() {
            let plugins = [
                AnyDebugDrawerPlugin(LayoutConsole()),
                AnyDebugDrawerPlugin(LayoutNetwork()),
                AnyDebugDrawerPlugin(LayoutKeychain()),
            ]
            var sut = DrawerLayout()
            let expected = ["Network", "Console"]

            sut.move("LayoutConsole", by: 1, among: plugins)

            let actual = sut.sections(for: plugins).first?.plugins.map(\.title)
            #expect(actual == expected)
        }

        @Test("Moving past either end of a group changes nothing")
        func movingPastTheEndsChangesNothing() {
            let plugins = [AnyDebugDrawerPlugin(LayoutConsole()), AnyDebugDrawerPlugin(LayoutNetwork())]
            var sut = DrawerLayout()
            let expected = DrawerLayout()

            sut.move("LayoutConsole", by: -1, among: plugins)
            sut.move("LayoutNetwork", by: 1, among: plugins)

            #expect(sut == expected)
        }

        @Test("Moving a pinned plugin reorders the pins")
        func movingAPinnedPluginReordersThePins() {
            let plugins = [AnyDebugDrawerPlugin(LayoutConsole()), AnyDebugDrawerPlugin(LayoutKeychain())]
            var sut = DrawerLayout()
            sut.togglePin("LayoutConsole")
            sut.togglePin("LayoutKeychain")
            let expected = ["LayoutKeychain", "LayoutConsole"]

            sut.move("LayoutKeychain", by: -1, among: plugins)

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
                AnyDebugDrawerPlugin(LayoutKeychain()),
            ]
            var expected = DrawerLayout()
            expected.togglePin("LayoutKeychain")
            expected.move("LayoutNetwork", by: -1, among: plugins)
            expected.lastUsed = "LayoutNetwork"

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
            sut.order = ["RemovedPlugin", "LayoutConsole"]
            let expected = [["Console"]]

            let actual = sut.sections(for: [AnyDebugDrawerPlugin(LayoutConsole())]).map { $0.plugins.map(\.title) }

            #expect(actual == expected)
        }

        @Test("No plugins give no groups")
        func noPluginsGiveNoGroups() {
            let actual = DrawerLayout().sections(for: [])

            #expect(actual.isEmpty)
        }
    }
#endif
