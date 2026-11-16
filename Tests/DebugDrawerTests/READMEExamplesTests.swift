// The README's examples, verbatim, so the README cannot drift from the code.

#if DEBUG
    import DebugDrawer
    import SwiftUI
    import Testing

    struct CachePlugin: DebugDrawerPlugin {
        var title = "Cache"
        var icon = "trash" // an SF Symbol

        var body: some View {
            Button("Clear URL cache") { URLCache.shared.removeAllCachedResponses() }
        }
    }

    @MainActor
    @Suite("README examples")
    struct READMEExamplesTests {
        @Test("Usage")
        func usage() {
            let wasOpen = DebugDrawer.shared.isOpen

            // Global: registered once at startup, always in the drawer.
            DebugDrawer.shared.registerGlobal(CachePlugin())

            // The drawer, attached once to the root view.
            let root = Text("Home").debugDrawer()

            // Local: in the drawer while its view is on screen.
            let settings = Text("Settings").debugLocalPlugin(CachePlugin())

            // Open or close it from whatever trigger suits the app.
            DebugDrawer.shared.toggle()

            _ = (root, settings)
            #expect(DebugDrawer.shared.globalPlugins.contains { $0.title == "Cache" })
            #expect(DebugDrawer.shared.isOpen != wasOpen)

            // Leave the shared drawer as the other suites expect it, within this one main-actor turn.
            DebugDrawer.shared.toggle()
            DebugDrawer.shared.unregisterGlobal(id: CachePlugin().id)
        }
    }
#endif
