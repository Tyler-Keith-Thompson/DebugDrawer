#if DEBUG
    @testable import DebugDrawer
    import Foundation
    import SwiftUI
    import Testing

    struct NamedInstancePlugin: DebugDrawerPlugin {
        var id: String
        var title: String
        var icon = "doc"
        var body: some View { EmptyView() }
    }

    struct UnnamedPlugin: DebugDrawerPlugin {
        var title = "Unnamed"
        var icon = "doc"
        var body: some View { EmptyView() }
    }

    private struct PrivatePlugin: DebugDrawerPlugin {
        var title = "Private"
        var icon = "doc"
        var body: some View { EmptyView() }
    }

    // Two plugins named alike in two namespaces, as two modules' `CachePlugin`s would be: their
    // unqualified names are the same.
    enum Billing {
        struct CachePlugin: DebugDrawerPlugin {
            var title = "Billing Cache"
            var icon = "creditcard"
            var body: some View { EmptyView() }
        }
    }

    enum Search {
        struct CachePlugin: DebugDrawerPlugin {
            var title = "Search Cache"
            var icon = "magnifyingglass"
            var body: some View { EmptyView() }
        }
    }

    // Each test that registers makes a drawer of its own over a UserDefaults suite named for the
    // test, removed when the test ends.
    @MainActor
    @Suite("Plugin identity")
    struct PluginIdentityTests {
        @Test("A plugin that declares its own id is identified by it, not by its type's name")
        func aDeclaredIDWins() {
            let expected = "document-1"

            let actual = AnyDebugDrawerPlugin(NamedInstancePlugin(id: "document-1", title: "Document")).id

            #expect(actual == expected)
        }

        @Test("A plugin that declares no id is identified by its type's fully qualified name")
        func theQualifiedTypeNameIsTheDefault() {
            let expected = "DebugDrawerTests.UnnamedPlugin"

            let actual = AnyDebugDrawerPlugin(UnnamedPlugin()).id

            #expect(actual == expected)
        }

        @Test("A private plugin type's default id names its module, without the context address that moves between launches")
        func aPrivateTypeIsNamedByItsModule() {
            let expected = "DebugDrawerTests.PrivatePlugin"

            let actual = AnyDebugDrawerPlugin(PrivatePlugin()).id

            #expect(actual == expected)
        }

        @Test("Two global plugins whose types share a name in different namespaces both register")
        func sameTypeNameInTwoNamespacesBothRegister() throws {
            let suite = "PluginIdentityTests.\(#function).\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let sut = DebugDrawer(defaults: defaults)
            let expected = ["DebugDrawerTests.Billing.CachePlugin", "DebugDrawerTests.Search.CachePlugin"]

            sut.registerGlobal(Billing.CachePlugin())
            sut.registerGlobal(Search.CachePlugin())

            #expect(sut.globalPlugins.map(\.id) == expected)
            #expect(sut.globalPlugins.map(\.title) == ["Billing Cache", "Search Cache"])
        }

        @Test("Two local plugins whose types share a name in different namespaces are both listed")
        func sameTypeNameInTwoNamespacesBothListLocally() throws {
            let suite = "PluginIdentityTests.\(#function).\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let sut = DebugDrawer(defaults: defaults)
            let expected = ["Billing Cache", "Search Cache"]

            sut.registerLocal(Billing.CachePlugin())
            sut.registerLocal(Search.CachePlugin())

            #expect(sut.localPlugins.map(\.title) == expected)
        }

        @Test("Registering a plugin of the same type under a registered id changes nothing and is no collision")
        func sameTypeIsAlreadyRegistered() {
            let registered = [AnyDebugDrawerPlugin(NamedInstancePlugin(id: "shared", title: "First"))]

            let actual = DrawerRegistrationOutcome(of: AnyDebugDrawerPlugin(NamedInstancePlugin(id: "shared", title: "Second")), among: registered)

            let isAlreadyRegistered = if case .alreadyRegistered = actual { true } else { false }
            #expect(isAlreadyRegistered)
        }

        @Test("Registering a plugin of another type under a registered id is a collision naming the registered type")
        func anotherTypeCollides() {
            let registered = [AnyDebugDrawerPlugin(NamedInstancePlugin(id: "shared", title: "First"))]
            let expected = "DebugDrawerTests.NamedInstancePlugin"

            let actual = DrawerRegistrationOutcome(of: AnyDebugDrawerPlugin(IDOverridingPlugin(id: "shared")), among: registered)

            let collidingTypeName: String? = if case let .collision(registered) = actual { registered.typeName } else { nil }
            #expect(collidingTypeName == expected)
        }

        @Test("A global plugin colliding with a registered one of another type leaves the first registered")
        func aCollidingGlobalLeavesTheFirst() throws {
            let suite = "PluginIdentityTests.\(#function).\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let sut = DebugDrawer(defaults: defaults)
            let expected = ["First"]

            sut.registerGlobal(NamedInstancePlugin(id: "shared", title: "First"))
            sut.registerGlobal(IDOverridingPlugin(id: "shared"))

            #expect(sut.globalPlugins.map(\.title) == expected)
        }

        @Test("Two instances of one type with different ids both register globally and keep separate collapsed state")
        func instancesWithDifferentIDsBothRegister() throws {
            let suite = "PluginIdentityTests.\(#function).\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let sut = DebugDrawer(defaults: defaults)
            let expectedIDs = ["document-1", "document-2"]

            sut.registerGlobal(NamedInstancePlugin(id: "document-1", title: "First"))
            sut.registerGlobal(NamedInstancePlugin(id: "document-2", title: "Second"))

            #expect(sut.globalPlugins.map(\.id) == expectedIDs)
            #expect(sut.globalPlugins[0].collapsedStateKey != sut.globalPlugins[1].collapsedStateKey)
        }

        @Test("Two instances of one type with different ids each get their own place in the layout")
        func instancesWithDifferentIDsAreSeparate() {
            let plugins = [
                AnyDebugDrawerPlugin(NamedInstancePlugin(id: "document-1", title: "First")),
                AnyDebugDrawerPlugin(NamedInstancePlugin(id: "document-2", title: "Second"))
            ]
            var sut = DrawerLayout()
            let expected = [["Second"], ["First"]]

            sut.togglePin("document-2")

            let actual = sut.sections(for: plugins).map { $0.plugins.map(\.title) }
            #expect(actual == expected)
        }

        @Test("State saved under a plugin's unqualified type name moves to its qualified id when it registers")
        func savedStateMovesToTheQualifiedID() throws {
            let suite = "PluginIdentityTests.\(#function).\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            var layout = DrawerLayout()
            layout.togglePin("UnnamedPlugin")
            layout.order = ["Other", "UnnamedPlugin"]
            layout.lastUsed = "UnnamedPlugin"
            layout.save(to: defaults)
            var hud = HUDLayout()
            hud.togglePin("UnnamedPlugin")
            hud.save(to: defaults)
            defaults.set(true, forKey: "com.debugdrawer.collapsed.UnnamedPlugin")
            defaults.set(["UnnamedPlugin"], forKey: DebugDrawer.noticesMutedDefaultsKey)
            let sut = DebugDrawer(defaults: defaults)
            let id = "DebugDrawerTests.UnnamedPlugin"

            sut.registerGlobal(UnnamedPlugin())

            let actualLayout = DrawerLayout(from: defaults)
            #expect(actualLayout.pinned == [id])
            #expect(actualLayout.order == ["Other", id])
            #expect(actualLayout.lastUsed == id)
            #expect(sut.hudLayout.pinned == [id])
            #expect(HUDLayout(from: defaults).pinned == [id])
            #expect(defaults.bool(forKey: "com.debugdrawer.collapsed.\(id)"))
            #expect(defaults.object(forKey: "com.debugdrawer.collapsed.UnnamedPlugin") == nil)
            #expect(sut.isNoticesMuted(forPlugin: id))
            #expect(!sut.isNoticesMuted(forPlugin: "UnnamedPlugin"))
        }

        @Test("State already saved under the qualified id wins over state saved under the unqualified name")
        func savedStateUnderTheIDWins() throws {
            let suite = "PluginIdentityTests.\(#function).\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set(true, forKey: "com.debugdrawer.collapsed.UnnamedPlugin")
            defaults.set(false, forKey: "com.debugdrawer.collapsed.DebugDrawerTests.UnnamedPlugin")
            let sut = DebugDrawer(defaults: defaults)

            sut.registerGlobal(UnnamedPlugin())

            #expect(!defaults.bool(forKey: "com.debugdrawer.collapsed.DebugDrawerTests.UnnamedPlugin"))
            #expect(defaults.object(forKey: "com.debugdrawer.collapsed.UnnamedPlugin") == nil)
        }

        @Test("A local plugin's state saved under its unqualified type name moves to its id when it registers")
        func localSavedStateMoves() throws {
            let suite = "PluginIdentityTests.\(#function).\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set(true, forKey: "com.debugdrawer.collapsed.UnnamedPlugin")
            let sut = DebugDrawer(defaults: defaults)

            sut.registerLocal(UnnamedPlugin())

            #expect(defaults.bool(forKey: "com.debugdrawer.collapsed.DebugDrawerTests.UnnamedPlugin"))
            #expect(defaults.object(forKey: "com.debugdrawer.collapsed.UnnamedPlugin") == nil)
        }

        @Test("A plugin that declares its own id moves no state saved under its type's name")
        func aDeclaredIDMovesNothing() throws {
            let suite = "PluginIdentityTests.\(#function).\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set(true, forKey: "com.debugdrawer.collapsed.NamedInstancePlugin")
            let sut = DebugDrawer(defaults: defaults)

            sut.registerGlobal(NamedInstancePlugin(id: "document-1", title: "Document"))

            #expect(defaults.bool(forKey: "com.debugdrawer.collapsed.NamedInstancePlugin"))
            #expect(defaults.object(forKey: "com.debugdrawer.collapsed.document-1") == nil)
        }
    }

    /// A plugin of another type than `NamedInstancePlugin` that takes the ID the test gives it.
    private struct IDOverridingPlugin: DebugDrawerPlugin {
        let id: String
        var title = "Overriding"
        var icon = "doc"
        var body: some View { EmptyView() }
    }
#endif
