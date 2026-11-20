#if DEBUG
    @testable import DebugDrawer
    import SwiftUI
    import Testing

    // ViewInspector isn't linked on visionOS (APPLE_ONLY_PACKAGE_EXCLUDED_PLATFORMS in
    // scripts/modules.py), so the tests that inspect views run everywhere else.
    #if !os(visionOS)
        import ViewInspector
    #endif

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
            drawer.close()
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
            let shown = DebugDrawer.shared.badges["DebugDrawerTests.NoticePlugin"]
            sut.clearBadge()

            #expect(shown == 3)
            #expect(DebugDrawer.shared.badges["DebugDrawerTests.NoticePlugin"] == nil)
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
            let expected = DebugDrawerToast(pluginID: "DebugDrawerTests.NoticePlugin", message: "Request 100 failed", count: 100)

            for request in 1 ... 100 {
                sut.postToast("Request \(request) failed")
            }

            #expect(DebugDrawer.shared.toast == expected)
        }

        @Test("A post from another plugin replaces the toast and restarts its count")
        func anotherPluginReplacesTheToast() {
            NoticePlugin().postToast("first")
            NoticePlugin().postToast("second")
            let expected = DebugDrawerToast(pluginID: "DebugDrawerTests.OtherNoticePlugin", message: "other", count: 1)

            OtherNoticePlugin().postToast("other")

            #expect(DebugDrawer.shared.toast == expected)
        }

        @Test("A post while the drawer is open is dropped")
        func aPostWhileOpenIsDropped() {
            DebugDrawer.shared.open()
            defer { DebugDrawer.shared.close() }

            NoticePlugin().postToast("ignored")

            #expect(DebugDrawer.shared.toast == nil)
        }

        @Test("Opening a toast opens the drawer at its plugin and removes the toast")
        func openingAToastRevealsItsPlugin() {
            NoticePlugin().postToast("Disk write on main")
            let sut = DebugDrawer.shared
            defer {
                sut.close()
                sut.revealRequest = nil
            }

            sut.openToast()

            #expect(sut.isOpen)
            #expect(sut.revealRequest == "DebugDrawerTests.NoticePlugin")
            #expect(sut.toast == nil)
        }

        @Test("Dismissing a toast removes it and leaves the drawer closed")
        func dismissingAToastLeavesTheDrawerClosed() {
            NoticePlugin().postToast("Disk write on main")

            DebugDrawer.shared.dismissToast()

            #expect(DebugDrawer.shared.toast == nil)
            #expect(!DebugDrawer.shared.isOpen)
        }

        #if !os(visionOS)
            @Test("The toast view shows the plugin's title, the latest message and the count")
            func theToastViewShowsItsContent() throws {
                let toast = DebugDrawerToast(pluginID: "DebugDrawerTests.NoticePlugin", message: "3 requests failed", count: 3)
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
                let toast = DebugDrawerToast(pluginID: "DebugDrawerTests.NoticePlugin", message: "failed", count: 1)
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

            // tvOS moves focus between the toast's buttons, so its dismiss button keeps its place
            // in the row and has no hit area to grow.
            #if !os(tvOS)
                @Test("The dismiss button's hit area is 44 points square on a touch screen and 22 on the Mac, at the toast's top trailing corner")
                func theDismissButtonsHitArea() throws {
                    let toast = DebugDrawerToast(pluginID: "DebugDrawerTests.NoticePlugin", message: "failed", count: 1)
                    let sut = DrawerToastView(toast: toast, plugin: nil, open: {}, dismiss: {})
                    #if os(macOS)
                        let expected: CGFloat = 22
                    #else
                        let expected: CGFloat = 44
                    #endif

                    let button = try sut.inspect().find(ViewType.Button.self) { try $0.accessibilityLabel().string() == "Dismiss" }
                    let actual = try button.find(ViewType.Image.self).flexFrame()

                    #expect(actual.minWidth == expected)
                    #expect(actual.minHeight == expected)
                    #expect(actual.alignment == .topTrailing)
                }
            #endif

            @Test("A toast leaving the screen ends the pointer's hold on it")
            func disappearingEndsThePointersHold() throws {
                var holds: [String] = []
                let toast = DebugDrawerToast(pluginID: "DebugDrawerTests.NoticePlugin", message: "failed", count: 1)
                let sut = DrawerToastView(toast: toast, plugin: nil, open: {}, dismiss: {}, hold: { hold, isHeld in
                    holds.append("\(hold) \(isHeld)")
                })
                let expected = ["pointer false"]

                try sut.inspect().hStack().callOnDisappear()

                #expect(holds == expected)
            }

            @Test("A section header shows its plugin's badge count")
            func aHeaderShowsTheBadge() throws {
                let sut = PluginHeaderLabel(plugin: AnyDebugDrawerPlugin(NoticePlugin()), isExpanded: false, isPinned: false, badge: 7)

                let actual = try sut.inspect().find(ViewType.Text.self) { try $0.accessibilityLabel().string() == "7 new" }

                #expect(throws: Never.self) { try actual.string() }
            }
        #endif
    }
#endif
