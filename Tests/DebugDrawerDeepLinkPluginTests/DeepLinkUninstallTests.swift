#if DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerDeepLinkPlugin
    import Foundation
    import Testing

    @MainActor
    @Suite("Deep Link Tester forgets the last outcome once removed from every drawer, keeping the history")
    struct DeepLinkUninstallTests {
        @Test("Unregistering removes the plugin and forgets the outcome; the history stays in memory and the defaults")
        func disappearsFromTheDrawer() async throws {
            let name = "DeepLinkUninstallTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: name))
            defer { defaults.removePersistentDomain(forName: name) }
            let drawer = DebugDrawer(defaults: defaults)
            let model = DeepLinkModel(delivery: _UserActivityDelivering(handler: nil), system: FakeSystemURLOpening(), defaults: defaults)
            let sut = DeepLinkPlugin(model: model)
            let url = try #require(URL(string: "shop://orders/42"))
            drawer.registerGlobal(sut)
            await model.open(url)
            let outcomeWhileInstalled = model.outcome

            drawer.unregisterGlobal(id: sut.id)

            #expect(outcomeWhileInstalled == .opened(url.absoluteString))
            #expect(!drawer.globalPlugins.contains { $0.id == sut.id })
            #expect(model.outcome == nil)
            #expect(model.history == [url.absoluteString])
            #expect(defaults.stringArray(forKey: DeepLinkModel.historyKey) == [url.absoluteString])
        }

        @Test("Uninstalling twice is harmless, and a plugin registered again opens URLs again")
        func uninstallTwiceThenReinstall() async throws {
            let name = "DeepLinkUninstallTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: name))
            defer { defaults.removePersistentDomain(forName: name) }
            let drawer = DebugDrawer(defaults: defaults)
            let model = DeepLinkModel(delivery: _UserActivityDelivering(handler: nil), system: FakeSystemURLOpening(), defaults: defaults)
            let sut = DeepLinkPlugin(model: model)
            let url = try #require(URL(string: "shop://cart"))
            drawer.registerGlobal(sut)
            drawer.unregisterGlobal(id: sut.id)

            sut.uninstall(from: drawer)
            drawer.registerGlobal(sut)
            await model.open(url)

            #expect(model.outcome == .opened(url.absoluteString))
        }
    }
#endif
