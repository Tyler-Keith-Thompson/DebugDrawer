#if DEBUG
    @testable import DebugDrawer
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

    // Serialized: these tests register on the one shared drawer.
    @MainActor
    @Suite("Plugin identity", .serialized)
    struct PluginIdentityTests {
        @Test("A plugin that declares its own id is identified by it, not by its type's name")
        func aDeclaredIDWins() {
            let expected = "document-1"

            let actual = AnyDebugDrawerPlugin(NamedInstancePlugin(id: "document-1", title: "Document")).id

            #expect(actual == expected)
        }

        @Test("contentIdentifier defaults to the declared id")
        func contentIdentifierDefaultsToTheDeclaredID() {
            let expected = "document-1"

            let actual = NamedInstancePlugin(id: "document-1", title: "Document").contentIdentifier

            #expect(actual == expected)
        }

        @Test("A plugin that declares no id is identified by its type's name")
        func theTypeNameIsTheDefault() {
            let expected = "UnnamedPlugin"

            let actual = AnyDebugDrawerPlugin(UnnamedPlugin()).id

            #expect(actual == expected)
        }

        @Test("Two instances of one type with different ids both register globally and keep separate collapsed state")
        func instancesWithDifferentIDsBothRegister() {
            let sut = DebugDrawer.shared
            defer {
                sut.unregisterGlobal(id: "document-1")
                sut.unregisterGlobal(id: "document-2")
            }
            let expectedIDs = ["document-1", "document-2"]

            sut.registerGlobal(NamedInstancePlugin(id: "document-1", title: "First"))
            sut.registerGlobal(NamedInstancePlugin(id: "document-2", title: "Second"))

            let registered = sut.globalPlugins.filter { $0.title == "First" || $0.title == "Second" }
            #expect(registered.map(\.id) == expectedIDs)
            #expect(registered[0].collapsedStateKey != registered[1].collapsedStateKey)
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
    }
#endif
