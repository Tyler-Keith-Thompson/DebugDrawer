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

    struct SessionPlugin: DebugDrawerPlugin {
        var title = "Session"
        var icon = "person.crop.circle"

        var body: some View {
            Text("Signed in")
        }

        var actions: [DebugDrawerAction] {
            [
                DebugDrawerAction("Expire token", keywords: ["auth", "logout"]) {
                    UserDefaults.standard.removeObject(forKey: "authToken")
                }
            ]
        }
    }

    struct UploadsPlugin: DebugDrawerPlugin {
        var title = "Uploads"
        var icon = "arrow.up.circle"

        var body: some View {
            Text("No uploads")
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

        @Test("Badges and toasts")
        func badgesAndToasts() {
            let wasOpen = DebugDrawer.shared.isOpen
            DebugDrawer.shared.isOpen = false

            let uploads = UploadsPlugin()
            uploads.setBadge(2)
            uploads.postToast("Upload of report.pdf failed")
            let badge = DebugDrawer.shared.badges["UploadsPlugin"]
            let toast = DebugDrawer.shared.toast
            uploads.clearBadge()

            // Leave the shared drawer as the other suites expect it, within this one main-actor turn.
            DebugDrawer.shared.dismissToast()
            DebugDrawer.shared.isOpen = wasOpen
            #expect(badge == 2)
            #expect(toast?.pluginID == "UploadsPlugin")
            #expect(toast?.message == "Upload of report.pdf failed")
            #expect(DebugDrawer.shared.badges["UploadsPlugin"] == nil)
        }

        @Test("Searching plugins and actions")
        func searchingPluginsAndActions() {
            let expectedTitles = ["Expire token"]

            let actual = AnyDebugDrawerPlugin(SessionPlugin()).actions.map(\.title)

            #expect(actual == expectedTitles)
            #expect(AnyDebugDrawerPlugin(CachePlugin()).actions.isEmpty)
        }
    }
#endif
