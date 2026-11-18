#if DEBUG
    @testable import DebugDrawer
    import Foundation
    import Testing

    // Every suite here has a unique name of the test's own, standing in for both the app's
    // standard defaults and the drawer's suite; nothing reads or writes the real ones.
    @Suite("The drawer's own defaults")
    struct DrawerDefaultsTests {
        @Test("The drawer's keys move from the app's defaults into the drawer's suite, and the app's own keys stay")
        func drawerKeysMove() throws {
            let sourceName = "DrawerDefaultsTests.source.\(UUID().uuidString)"
            let suiteName = "DrawerDefaultsTests.suite.\(UUID().uuidString)"
            let source = try #require(UserDefaults(suiteName: sourceName))
            defer { source.removePersistentDomain(forName: sourceName) }
            defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
            let layout = Data("{}".utf8)
            source.set(true, forKey: "com.debugdrawer.collapsed.MyApp.CachePlugin")
            source.set(layout, forKey: "com.debugdrawer.layout")
            source.set(["https://example.com"], forKey: "com.debugdrawer.deeplink.history")
            source.set(true, forKey: "com.debugdrawer.location.enabled")
            source.set(true, forKey: "com.debugdrawer.screenRecording.showsTouches")
            source.set("on", forKey: "com.debugdrawer.tweaks.darkMode")
            source.set(true, forKey: "onboarded")

            let sut = UserDefaults.debugDrawerSuite(named: suiteName, movingKeysFrom: source)

            #expect(sut.bool(forKey: "com.debugdrawer.collapsed.MyApp.CachePlugin"))
            #expect(sut.data(forKey: "com.debugdrawer.layout") == layout)
            #expect(sut.stringArray(forKey: "com.debugdrawer.deeplink.history") == ["https://example.com"])
            #expect(sut.bool(forKey: "com.debugdrawer.location.enabled"))
            #expect(sut.bool(forKey: "com.debugdrawer.screenRecording.showsTouches"))
            #expect(source.object(forKey: "com.debugdrawer.collapsed.MyApp.CachePlugin") == nil)
            #expect(source.object(forKey: "com.debugdrawer.layout") == nil)
            #expect(source.object(forKey: "com.debugdrawer.deeplink.history") == nil)
            #expect(source.object(forKey: "com.debugdrawer.location.enabled") == nil)
            #expect(source.object(forKey: "com.debugdrawer.screenRecording.showsTouches") == nil)
            #expect(source.string(forKey: "com.debugdrawer.tweaks.darkMode") == "on")
            #expect(source.bool(forKey: "onboarded"))
            #expect(sut.object(forKey: "onboarded") == nil)
        }

        @Test("A key the drawer's suite already holds keeps its value, and the app's copy is still removed")
        func theSuiteWins() throws {
            let sourceName = "DrawerDefaultsTests.source.\(UUID().uuidString)"
            let suiteName = "DrawerDefaultsTests.suite.\(UUID().uuidString)"
            let source = try #require(UserDefaults(suiteName: sourceName))
            let suite = try #require(UserDefaults(suiteName: suiteName))
            defer { source.removePersistentDomain(forName: sourceName) }
            defer { suite.removePersistentDomain(forName: suiteName) }
            source.set(["Old"], forKey: "com.debugdrawer.noticesMuted")
            suite.set(["New"], forKey: "com.debugdrawer.noticesMuted")
            let expected = ["New"]

            let sut = UserDefaults.debugDrawerSuite(named: suiteName, movingKeysFrom: source)

            #expect(sut.stringArray(forKey: "com.debugdrawer.noticesMuted") == expected)
            #expect(source.object(forKey: "com.debugdrawer.noticesMuted") == nil)
        }

        @Test("The keys move once: a drawer key written to the app's defaults after the move stays there")
        func theMoveHappensOnce() throws {
            let sourceName = "DrawerDefaultsTests.source.\(UUID().uuidString)"
            let suiteName = "DrawerDefaultsTests.suite.\(UUID().uuidString)"
            let source = try #require(UserDefaults(suiteName: sourceName))
            defer { source.removePersistentDomain(forName: sourceName) }
            defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
            _ = UserDefaults.debugDrawerSuite(named: suiteName, movingKeysFrom: source)
            source.set(Data("{}".utf8), forKey: "com.debugdrawer.hud")

            let sut = UserDefaults.debugDrawerSuite(named: suiteName, movingKeysFrom: source)

            #expect(source.data(forKey: "com.debugdrawer.hud") != nil)
            #expect(sut.data(forKey: "com.debugdrawer.hud") == nil)
        }

        @MainActor
        @Test("The shared drawer saves to the drawer's suite, not the app's standard defaults")
        func theSharedDrawerSavesToItsSuite() {
            let actual = DebugDrawer.shared.defaults

            #expect(actual === UserDefaults.debugDrawer)
            #expect(actual !== UserDefaults.standard)
        }
    }
#endif
