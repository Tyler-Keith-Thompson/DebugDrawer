#if DEBUG
    @testable import DebugDrawer
    import SwiftUI
    import Testing

    struct TestPlugin: DebugDrawerPlugin {
        var title: String
        var icon = "gear"
        var body: some View { Text("test") }
    }

    // Serialized: every test works on the one shared drawer.
    @MainActor
    @Suite("DebugDrawer registry", .serialized)
    struct DebugDrawerTests {
        init() {
            let drawer = DebugDrawer.shared
            for plugin in drawer.globalPlugins {
                drawer.unregisterGlobal(id: plugin.id)
            }
        }

        @Test("Registering a global plugin lists it")
        func registerGlobalPlugin() {
            let sut = DebugDrawer.shared
            #expect(sut.globalPlugins.isEmpty)

            sut.registerGlobal(TestPlugin(title: "A"))

            #expect(sut.globalPlugins.count == 1)
            #expect(sut.globalPlugins.first?.title == "A")
        }

        @Test("A second global plugin with the same ID is ignored")
        func duplicateGlobalIgnored() {
            let sut = DebugDrawer.shared

            sut.registerGlobal(TestPlugin(title: "A"))
            sut.registerGlobal(TestPlugin(title: "A")) // same ID (type name)

            #expect(sut.globalPlugins.count == 1)
        }

        @Test("Unregistering a global plugin removes it")
        func unregisterGlobal() {
            let sut = DebugDrawer.shared
            sut.registerGlobal(TestPlugin(title: "A"))

            sut.unregisterGlobal(id: "TestPlugin")

            #expect(sut.globalPlugins.isEmpty)
        }

        @Test("A local plugin is removed by the token its registration returned")
        func localPluginToken() {
            let sut = DebugDrawer.shared
            let token = sut.registerLocal(TestPlugin(title: "Local"))
            #expect(sut.localPlugins.count == 1)

            sut.unregisterLocal(id: "TestPlugin", token: token)

            #expect(sut.localPlugins.isEmpty)
        }

        @Test("A stale token does not remove a newer registration of the same plugin")
        func staleTokenNoOp() {
            let sut = DebugDrawer.shared
            let oldToken = sut.registerLocal(TestPlugin(title: "Local"))
            let newToken = sut.registerLocal(TestPlugin(title: "Updated"))

            sut.unregisterLocal(id: "TestPlugin", token: oldToken)
            #expect(sut.localPlugins.count == 1)

            sut.unregisterLocal(id: "TestPlugin", token: newToken)
            #expect(sut.localPlugins.isEmpty)
        }

        @Test("The drawer has plugins once one is registered")
        func hasPlugins() {
            let sut = DebugDrawer.shared
            #expect(!sut.hasPlugins)

            sut.registerGlobal(TestPlugin(title: "A"))

            #expect(sut.hasPlugins)
        }

        @Test("Toggling opens a closed drawer and closes an open one")
        func toggle() {
            let sut = DebugDrawer.shared
            #expect(!sut.isOpen)

            sut.toggle()
            #expect(sut.isOpen)

            sut.toggle()
            #expect(!sut.isOpen)
        }
    }
#endif
