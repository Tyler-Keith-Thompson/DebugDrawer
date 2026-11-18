#if DEBUG
    @testable import DebugDrawer
    import DebugDrawerLoadedLibrariesPlugin
    import Foundation
    import SwiftUI
    import Testing

    /// An app's own plugin that happens to share its name with the shipped Loaded Libraries plugin
    /// in another module, and takes the default id.
    struct LoadedLibrariesPlugin: DebugDrawerPlugin {
        var title = "App's Libraries"
        var icon = "books.vertical"
        var body: some View { EmptyView() }
    }

    @MainActor
    @Suite("Plugin identity across modules")
    struct PluginIdentityAcrossModulesTests {
        @Test("A plugin named like one in another module registers beside it rather than being dropped")
        func samePluginNameInTwoModulesBothRegister() throws {
            let suite = "PluginIdentityAcrossModulesTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let sut = DebugDrawer(defaults: defaults)
            let expectedIDs = ["LoadedLibrariesPlugin", "DebugDrawerLoadedLibrariesPluginTests.LoadedLibrariesPlugin"]
            let expectedTitles = ["Loaded Libraries", "App's Libraries"]

            sut.registerGlobal(DebugDrawerLoadedLibrariesPlugin.LoadedLibrariesPlugin())
            sut.registerGlobal(LoadedLibrariesPlugin())

            #expect(sut.globalPlugins.map(\.id) == expectedIDs)
            #expect(sut.globalPlugins.map(\.title) == expectedTitles)
        }
    }
#endif
