#if DEBUG
    @testable import DebugDrawer
    import Foundation
    import Testing

    // Each test makes a drawer of its own over a UserDefaults suite of its own, removed when the
    // test ends, so the mute state it saves reaches no other test and not the shared drawer.
    @MainActor
    @Suite("Silencing a plugin's notices")
    struct NoticeMutingTests {
        @Test("A plugin's notices are allowed until silenced")
        func noticesAreAllowedByDefault() throws {
            let name = "NoticeMutingTests.\(UUID().uuidString)"
            let suite = try #require(UserDefaults(suiteName: name))
            defer { suite.removePersistentDomain(forName: name) }
            let sut = DebugDrawer(defaults: suite)

            let actual = sut.isNoticesMuted(forPlugin: "Chatty")

            #expect(!actual)
        }

        @Test("While a plugin is silenced, its badge shows nothing and its toast is not raised")
        func silencedPluginRaisesNothing() throws {
            let name = "NoticeMutingTests.\(UUID().uuidString)"
            let suite = try #require(UserDefaults(suiteName: name))
            defer { suite.removePersistentDomain(forName: name) }
            let sut = DebugDrawer(defaults: suite)
            sut.setNoticesMuted(true, forPlugin: "Chatty")

            sut.setBadge(5, forPlugin: "Chatty")
            sut.postToast("Request failed", fromPlugin: "Chatty")

            #expect(sut.badges["Chatty"] == nil)
            #expect(sut.toast == nil)
        }

        @Test("Silencing one plugin leaves another plugin's badge and toast")
        func silencingIsPerPlugin() throws {
            let name = "NoticeMutingTests.\(UUID().uuidString)"
            let suite = try #require(UserDefaults(suiteName: name))
            defer { suite.removePersistentDomain(forName: name) }
            let sut = DebugDrawer(defaults: suite)
            let expected = DebugDrawerToast(pluginID: "Quiet", message: "Disk write on main", count: 1)
            sut.setNoticesMuted(true, forPlugin: "Chatty")

            sut.setBadge(2, forPlugin: "Quiet")
            sut.postToast("Disk write on main", fromPlugin: "Quiet")

            #expect(sut.badges["Quiet"] == 2)
            #expect(sut.toast == expected)
            #expect(!sut.isNoticesMuted(forPlugin: "Quiet"))
        }

        @Test("Silencing a plugin removes the badge and toast it already shows")
        func silencingRemovesCurrentNotices() throws {
            let name = "NoticeMutingTests.\(UUID().uuidString)"
            let suite = try #require(UserDefaults(suiteName: name))
            defer { suite.removePersistentDomain(forName: name) }
            let sut = DebugDrawer(defaults: suite)
            sut.setBadge(3, forPlugin: "Chatty")
            sut.postToast("Request failed", fromPlugin: "Chatty")

            sut.setNoticesMuted(true, forPlugin: "Chatty")

            #expect(sut.badges["Chatty"] == nil)
            #expect(sut.toast == nil)
            #expect(sut.isNoticesMuted(forPlugin: "Chatty"))
        }

        @Test("Silencing a plugin leaves another plugin's toast on screen")
        func silencingLeavesAnotherPluginsToast() throws {
            let name = "NoticeMutingTests.\(UUID().uuidString)"
            let suite = try #require(UserDefaults(suiteName: name))
            defer { suite.removePersistentDomain(forName: name) }
            let sut = DebugDrawer(defaults: suite)
            let expected = DebugDrawerToast(pluginID: "Quiet", message: "Disk write on main", count: 1)
            sut.postToast("Disk write on main", fromPlugin: "Quiet")

            sut.setNoticesMuted(true, forPlugin: "Chatty")

            #expect(sut.toast == expected)
        }

        @Test("Allowing a plugin's notices again shows the badges and toasts it sets afterwards")
        func allowingShowsLaterNotices() throws {
            let name = "NoticeMutingTests.\(UUID().uuidString)"
            let suite = try #require(UserDefaults(suiteName: name))
            defer { suite.removePersistentDomain(forName: name) }
            let sut = DebugDrawer(defaults: suite)
            let expected = DebugDrawerToast(pluginID: "Chatty", message: "Request failed", count: 1)
            sut.setNoticesMuted(true, forPlugin: "Chatty")
            sut.setBadge(5, forPlugin: "Chatty")

            sut.setNoticesMuted(false, forPlugin: "Chatty")
            let badgeOnUnmute = sut.badges["Chatty"]
            sut.setBadge(4, forPlugin: "Chatty")
            sut.postToast("Request failed", fromPlugin: "Chatty")

            #expect(badgeOnUnmute == nil)
            #expect(sut.badges["Chatty"] == 4)
            #expect(sut.toast == expected)
            #expect(!sut.isNoticesMuted(forPlugin: "Chatty"))
        }

        @Test("A new drawer reading the same UserDefaults sees the plugin as silenced, and as allowed once allowed again")
        func muteStateSurvivesRelaunch() throws {
            let name = "NoticeMutingTests.\(UUID().uuidString)"
            let suite = try #require(UserDefaults(suiteName: name))
            defer { suite.removePersistentDomain(forName: name) }
            let first = DebugDrawer(defaults: suite)
            first.setNoticesMuted(true, forPlugin: "Chatty")

            let relaunched = DebugDrawer(defaults: try #require(UserDefaults(suiteName: name)))
            let mutedAfterRelaunch = relaunched.isNoticesMuted(forPlugin: "Chatty")
            relaunched.setBadge(5, forPlugin: "Chatty")
            relaunched.setNoticesMuted(false, forPlugin: "Chatty")
            let allowedAfterSecondRelaunch = !DebugDrawer(defaults: suite).isNoticesMuted(forPlugin: "Chatty")

            #expect(mutedAfterRelaunch)
            #expect(relaunched.badges["Chatty"] == nil)
            #expect(allowedAfterSecondRelaunch)
        }
    }
#endif
