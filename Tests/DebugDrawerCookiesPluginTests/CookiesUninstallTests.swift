#if DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerCookiesPlugin
    import Foundation
    import Testing

    @MainActor
    @Suite("HTTP Cookies drops the cookies it read once removed from every drawer")
    struct CookiesUninstallTests {
        private static func drawer() throws -> (DebugDrawer, () -> Void) {
            let suite = "CookiesUninstallTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            return (DebugDrawer(defaults: defaults), { defaults.removePersistentDomain(forName: suite) })
        }

        @Test("Unregistering removes the plugin and drops the cookies read, keeping the filter and the stores' cookies")
        func disappearsFromTheDrawer() async throws {
            let (drawer, cleanUp) = try Self.drawer()
            defer { cleanUp() }
            let jar = FakeCookieJar([CookieFixtures.stored("session")])
            let model = CookiesModel(jar: jar)
            let sut = CookiesPlugin(model: model)
            drawer.registerGlobal(sut)
            await model.reload()
            model.filter = "sess"
            let readWhileInstalled = model.allCookies.count

            drawer.unregisterGlobal(id: sut.id)

            #expect(readWhileInstalled == 1)
            #expect(!drawer.globalPlugins.contains { $0.id == sut.id })
            #expect(model.allCookies.isEmpty)
            #expect(model.filter == "sess")
            #expect(jar.stored.count == 1)
        }

        @Test("Uninstalling twice is harmless, and once registered again the stores are read again")
        func uninstallTwiceThenReinstall() async throws {
            let (drawer, cleanUp) = try Self.drawer()
            defer { cleanUp() }
            let model = CookiesModel(jar: FakeCookieJar([CookieFixtures.stored("session")]))
            let sut = CookiesPlugin(model: model)
            drawer.registerGlobal(sut)
            drawer.unregisterGlobal(id: sut.id)

            sut.uninstall(from: drawer)
            drawer.registerGlobal(sut)
            await model.reload()

            #expect(model.allCookies.count == 1)
        }
    }
#endif
