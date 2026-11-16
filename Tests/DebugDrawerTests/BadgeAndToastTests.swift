#if DEBUG
    @testable import DebugDrawer
    import SwiftUI
    import Testing
    import ViewInspector

    struct NoticePlugin: DebugDrawerPlugin {
        var title = "Notices"
        var icon = "bell"
        var body: some View { EmptyView() }
    }

    struct OtherNoticePlugin: DebugDrawerPlugin {
        var title = "Other"
        var icon = "bell"
        var body: some View { EmptyView() }
    }

    // Serialized: every test works on the one shared drawer.
    @MainActor
    @Suite("Badges and toasts", .serialized)
    struct BadgeAndToastTests {
        init() {
            let drawer = DebugDrawer.shared
            drawer.isOpen = false
            drawer.dismissToast()
            drawer.revealRequest = nil
            for id in drawer.badges.keys {
                drawer.setBadge(0, forPlugin: id)
            }
        }

        @Test("A plugin's badge shows its count, and clearing it removes it")
        func aBadgeShowsItsCountUntilCleared() {
            let sut = NoticePlugin()

            sut.setBadge(3)
            let shown = DebugDrawer.shared.badges["NoticePlugin"]
            sut.clearBadge()

            #expect(shown == 3)
            #expect(DebugDrawer.shared.badges["NoticePlugin"] == nil)
        }

        @Test("A badge of zero or less clears it")
        func aBadgeOfZeroOrLessClears() {
            let sut = NoticePlugin()
            sut.setBadge(2)

            sut.setBadge(-1)

            #expect(DebugDrawer.shared.badges.isEmpty)
        }

        @Test("A burst of 100 posts from one plugin in one run-loop turn shows a single toast that counts them")
        func aBurstShowsOneToast() {
            let sut = NoticePlugin()
            let expected = DebugDrawerToast(pluginID: "NoticePlugin", message: "Request 100 failed", count: 100)

            for request in 1 ... 100 {
                sut.postToast("Request \(request) failed")
            }

            #expect(DebugDrawer.shared.toast == expected)
        }

        @Test("A post from another plugin replaces the toast and restarts its count")
        func anotherPluginReplacesTheToast() {
            NoticePlugin().postToast("first")
            NoticePlugin().postToast("second")
            let expected = DebugDrawerToast(pluginID: "OtherNoticePlugin", message: "other", count: 1)

            OtherNoticePlugin().postToast("other")

            #expect(DebugDrawer.shared.toast == expected)
        }

        @Test("A post while the drawer is open is dropped")
        func aPostWhileOpenIsDropped() {
            DebugDrawer.shared.isOpen = true
            defer { DebugDrawer.shared.isOpen = false }

            NoticePlugin().postToast("ignored")

            #expect(DebugDrawer.shared.toast == nil)
        }

        @Test("Opening a toast opens the drawer at its plugin and removes the toast")
        func openingAToastRevealsItsPlugin() {
            NoticePlugin().postToast("Disk write on main")
            let sut = DebugDrawer.shared
            defer {
                sut.isOpen = false
                sut.revealRequest = nil
            }

            sut.openToast()

            #expect(sut.isOpen)
            #expect(sut.revealRequest == "NoticePlugin")
            #expect(sut.toast == nil)
        }

        @Test("Dismissing a toast removes it and leaves the drawer closed")
        func dismissingAToastLeavesTheDrawerClosed() {
            NoticePlugin().postToast("Disk write on main")

            DebugDrawer.shared.dismissToast()

            #expect(DebugDrawer.shared.toast == nil)
            #expect(!DebugDrawer.shared.isOpen)
        }

        @Test("The toast view shows the plugin's title, the latest message and the count")
        func theToastViewShowsItsContent() throws {
            let toast = DebugDrawerToast(pluginID: "NoticePlugin", message: "3 requests failed", count: 3)
            let sut = DrawerToastView(toast: toast, plugin: AnyDebugDrawerPlugin(NoticePlugin()), open: {}, dismiss: {})

            let inspected = try sut.inspect()

            #expect(throws: Never.self) { try inspected.find(text: "Notices") }
            #expect(throws: Never.self) { try inspected.find(text: "3 requests failed") }
            #expect(throws: Never.self) { try inspected.find(text: "3") }
        }

        @Test("Tapping the toast opens it; the dismiss button dismisses it")
        func theToastViewsButtonsCallBack() throws {
            var opened = 0
            var dismissed = 0
            let toast = DebugDrawerToast(pluginID: "NoticePlugin", message: "failed", count: 1)
            let sut = DrawerToastView(
                toast: toast,
                plugin: nil,
                open: { opened += 1 },
                dismiss: { dismissed += 1 }
            )

            try sut.inspect().find(ViewType.Button.self) { try $0.accessibilityLabel().string() == "Dismiss" }.tap()
            try sut.inspect().find(ViewType.Button.self) { try $0.accessibilityHint().string() == "Opens the debug drawer at this plugin" }.tap()

            #expect(opened == 1)
            #expect(dismissed == 1)
        }

        @Test("A section header shows its plugin's badge count")
        func aHeaderShowsTheBadge() throws {
            let sut = PluginHeaderLabel(plugin: AnyDebugDrawerPlugin(NoticePlugin()), isExpanded: false, isPinned: false, badge: 7)

            let actual = try sut.inspect().find(ViewType.Text.self) { try $0.accessibilityLabel().string() == "7 new" }

            #expect(throws: Never.self) { try actual.string() }
        }
    }
#endif
