#if DEBUG
    @testable import DebugDrawer
    import DebugDrawerTestSupport
    import SwiftUI
    import Testing

    /// A plugin that raises badges and toasts, under an ID the test gives it, so no other test's
    /// drawer holds a plugin of that ID and the posts of one test reach no other.
    struct PostingPlugin: DebugDrawerPlugin {
        let id: String
        var title = "Uploads"
        var icon = "bell"
        var body: some View { EmptyView() }
    }

    // Each test makes the drawers it installs the plugin in, over UserDefaults suites named for
    // the test and removed when it ends. They only read the shared drawer, under an ID no other
    // test uses, so they run alongside the rest.
    @MainActor
    @Suite("Badges and toasts a plugin raises in the drawers that hold it")
    struct PluginNoticeTests {
        @Test("A plugin in a drawer of its own badges that drawer until cleared, and not the shared one")
        func aBadgeReachesTheDrawerThatHoldsThePlugin() throws {
            let suite = temporarySuiteName("PluginNoticeTests.\(#function)")
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let drawer = DebugDrawer(defaults: defaults)
            let sut = PostingPlugin(id: "PluginNoticeTests.\(UUID().uuidString)")
            drawer.registerGlobal(sut)

            sut.setBadge(3)
            let shown = drawer.badges[sut.id]
            let sharedShown = DebugDrawer.shared.badges[sut.id]
            sut.clearBadge()

            #expect(shown == 3)
            #expect(sharedShown == nil)
            #expect(drawer.badges[sut.id] == nil)
        }

        @Test("A plugin in a drawer of its own posts to that drawer as one toast that counts the posts, and not to the shared one")
        func aToastReachesTheDrawerThatHoldsThePlugin() throws {
            let suite = temporarySuiteName("PluginNoticeTests.\(#function)")
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let drawer = DebugDrawer(defaults: defaults)
            let sut = PostingPlugin(id: "PluginNoticeTests.\(UUID().uuidString)")
            drawer.registerGlobal(sut)
            let expected = DebugDrawerToast(pluginID: sut.id, message: "Request 2 failed", count: 2)

            sut.postToast("Request 1 failed")
            sut.postToast("Request 2 failed")

            #expect(drawer.toast == expected)
            #expect(DebugDrawer.shared.toast?.pluginID != sut.id)
        }

        @Test("A plugin in two drawers badges and toasts both, and clearing its badge clears both")
        func aPluginInTwoDrawersReachesBoth() throws {
            let firstSuite = temporarySuiteName("PluginNoticeTests.\(#function).first")
            let secondSuite = temporarySuiteName("PluginNoticeTests.\(#function).second")
            let firstDefaults = try #require(UserDefaults(suiteName: firstSuite))
            let secondDefaults = try #require(UserDefaults(suiteName: secondSuite))
            defer {
                firstDefaults.removePersistentDomain(forName: firstSuite)
                secondDefaults.removePersistentDomain(forName: secondSuite)
            }
            let first = DebugDrawer(defaults: firstDefaults)
            let second = DebugDrawer(defaults: secondDefaults)
            let sut = PostingPlugin(id: "PluginNoticeTests.\(UUID().uuidString)")
            first.registerGlobal(sut)
            second.registerGlobal(sut)
            let expected = DebugDrawerToast(pluginID: sut.id, message: "Upload failed", count: 1)

            sut.setBadge(2)
            sut.postToast("Upload failed")
            let shown = [first.badges[sut.id], second.badges[sut.id]]
            sut.clearBadge()

            #expect(shown == [2, 2])
            #expect(first.toast == expected)
            #expect(second.toast == expected)
            #expect(first.badges[sut.id] == nil)
            #expect(second.badges[sut.id] == nil)
            #expect(DebugDrawer.shared.badges[sut.id] == nil)
            #expect(DebugDrawer.shared.toast?.pluginID != sut.id)
        }

        @Test("A plugin registered as local in a drawer of its own badges and toasts that drawer")
        func aLocalPluginReachesItsDrawer() throws {
            let suite = temporarySuiteName("PluginNoticeTests.\(#function)")
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let drawer = DebugDrawer(defaults: defaults)
            let sut = PostingPlugin(id: "PluginNoticeTests.\(UUID().uuidString)")
            let token = drawer.registerLocal(sut)
            defer { drawer.unregisterLocal(id: sut.id, token: token) }

            sut.setBadge(1)
            sut.postToast("Saved the order")

            #expect(drawer.badges[sut.id] == 1)
            #expect(drawer.toast?.pluginID == sut.id)
            #expect(DebugDrawer.shared.badges[sut.id] == nil)
        }

        @Test("A copy of the plugin made after it was installed reaches the drawer the original was installed in")
        func aCopyOfThePluginReachesItsDrawer() throws {
            let suite = temporarySuiteName("PluginNoticeTests.\(#function)")
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let drawer = DebugDrawer(defaults: defaults)
            let id = "PluginNoticeTests.\(UUID().uuidString)"
            drawer.registerGlobal(PostingPlugin(id: id))
            let sut = PostingPlugin(id: id, title: "Uploads, again")

            sut.setBadge(4)

            #expect(drawer.badges[id] == 4)
        }

        @Test("Finding a plugin's drawers keeps none of them alive")
        func trackingKeepsNoDrawerAlive() throws {
            let suite = temporarySuiteName("PluginNoticeTests.\(#function)")
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let id = "PluginNoticeTests.\(UUID().uuidString)"
            weak var freed: DebugDrawer?
            do {
                let drawer = DebugDrawer(defaults: defaults)
                drawer.registerGlobal(PostingPlugin(id: id))
                freed = drawer
            }

            let actual = DebugDrawer.drawers(holdingPlugin: id)

            #expect(freed == nil)
            #expect(actual.count == 1)
            #expect(actual.first === DebugDrawer.shared)
        }
    }

    // A plugin no drawer of its own holds posts to the shared drawer, so these tests nest in the
    // serialized suite of the shared drawer's tests.
    extension SharedDrawerTests {
        @MainActor
        @Suite("Badges and toasts a plugin raises in the shared drawer")
        struct SharedPluginNoticeTests {
            init() {
                let drawer = DebugDrawer.shared
                drawer.close()
                drawer.dismissToast()
                drawer.revealRequest = nil
            }

            @Test("A plugin in the shared drawer alone badges and toasts the shared drawer, and no other")
            func aPluginInTheSharedDrawerReachesIt() throws {
                let suite = temporarySuiteName("SharedPluginNoticeTests.\(#function)")
                let defaults = try #require(UserDefaults(suiteName: suite))
                defer { defaults.removePersistentDomain(forName: suite) }
                let other = DebugDrawer(defaults: defaults)
                let sut = PostingPlugin(id: "SharedPluginNoticeTests.\(UUID().uuidString)")
                DebugDrawer.shared.registerGlobal(sut)
                defer {
                    DebugDrawer.shared.dismissToast()
                    DebugDrawer.shared.unregisterGlobal(id: sut.id)
                }
                let expected = DebugDrawerToast(pluginID: sut.id, message: "Upload failed", count: 1)

                sut.setBadge(2)
                sut.postToast("Upload failed")
                let shown = DebugDrawer.shared.badges[sut.id]
                let toast = DebugDrawer.shared.toast
                sut.clearBadge()

                #expect(shown == 2)
                #expect(toast == expected)
                #expect(DebugDrawer.shared.badges[sut.id] == nil)
                #expect(other.badges[sut.id] == nil)
                #expect(other.toast == nil)
            }

            @Test("A plugin no drawer holds badges and toasts the shared drawer")
            func aPluginInNoDrawerReachesTheSharedDrawer() {
                let sut = PostingPlugin(id: "SharedPluginNoticeTests.\(UUID().uuidString)")
                defer { DebugDrawer.shared.dismissToast() }
                let expected = DebugDrawerToast(pluginID: sut.id, message: "Upload failed", count: 1)

                sut.setBadge(5)
                sut.postToast("Upload failed")
                let shown = DebugDrawer.shared.badges[sut.id]
                sut.clearBadge()

                #expect(shown == 5)
                #expect(DebugDrawer.shared.toast == expected)
                #expect(DebugDrawer.shared.badges[sut.id] == nil)
            }

            @Test("A plugin removed from the only drawer of its own that held it posts to the shared drawer again")
            func aRemovedPluginFallsBackToTheSharedDrawer() throws {
                let suite = temporarySuiteName("SharedPluginNoticeTests.\(#function)")
                let defaults = try #require(UserDefaults(suiteName: suite))
                defer { defaults.removePersistentDomain(forName: suite) }
                let drawer = DebugDrawer(defaults: defaults)
                let sut = PostingPlugin(id: "SharedPluginNoticeTests.\(UUID().uuidString)")
                drawer.registerGlobal(sut)
                drawer.unregisterGlobal(id: sut.id)
                defer { DebugDrawer.shared.setBadge(0, forPlugin: sut.id) }

                sut.setBadge(1)

                #expect(drawer.badges[sut.id] == nil)
                #expect(DebugDrawer.shared.badges[sut.id] == 1)
            }
        }
    }
#endif
