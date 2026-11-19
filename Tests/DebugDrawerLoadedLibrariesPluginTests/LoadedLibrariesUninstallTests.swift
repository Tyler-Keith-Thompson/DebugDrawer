#if DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerLoadedLibrariesPlugin
    import Foundation
    import Testing

    @MainActor
    @Suite("Loaded Libraries leaves the drawer with nothing behind")
    struct LoadedLibrariesUninstallTests {
        @Test("Unregistering removes the plugin; uninstalling again is harmless, and registering again lists it once")
        func disappearsFromTheDrawer() throws {
            let suite = "LoadedLibrariesUninstallTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let drawer = DebugDrawer(defaults: defaults)
            let sut = LoadedLibrariesPlugin()
            drawer.registerGlobal(sut)

            drawer.unregisterGlobal(id: sut.id)
            let listedOnceRemoved = drawer.globalPlugins.contains { $0.id == sut.id }
            sut.uninstall(from: drawer)
            drawer.registerGlobal(sut)

            #expect(!listedOnceRemoved)
            #expect(drawer.globalPlugins.count { $0.id == sut.id } == 1)
        }
    }
#endif
