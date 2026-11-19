#if DEBUG && !os(watchOS)
    @testable import DebugDrawer
    import SwiftUI
    import Testing

    @MainActor
    struct DrawerJumpBarTests {
        @Test("The jump bar shows the version with the build in parentheses, either alone, or nothing")
        func release() {
            let both = DrawerJumpBar.Context(appName: "Orders", version: "1.4.2", build: "88", device: "iPad", system: "iOS 27.2")
            let versionOnly = DrawerJumpBar.Context(appName: "Orders", version: "2.0", build: nil, device: "Mac", system: "macOS 27.0")
            let buildOnly = DrawerJumpBar.Context(appName: "Orders", version: nil, build: "7", device: "Mac", system: "macOS 27.0")
            let neither = DrawerJumpBar.Context(appName: "Orders", version: nil, build: nil, device: "Mac", system: "macOS 27.0")
            let expected: [String?] = ["1.4.2 (88)", "2.0", "(7)", nil]

            let actual = [both, versionOnly, buildOnly, neither].map(\.release)

            #expect(actual == expected)
        }

        @Test("The jump bar shows the version alone when the build is the same string")
        func buildRepeatsVersion() {
            let sut = DrawerJumpBar.Context(appName: "DebugDrawerExample", version: "1.0.0", build: "1.0.0", device: "iPhone", system: "iOS 27.2")
            let expected: String? = "1.0.0"

            let actual = sut.release

            #expect(actual == expected)
        }

        @Test("VoiceOver reads the jump bar's parts joined by commas, the version named, a missing one left out")
        func spoken() {
            let full = DrawerJumpBar.Context(appName: "Orders", version: "1.4.2", build: "88", device: "iPad", system: "iOS 27.2")
            let bare = DrawerJumpBar.Context(appName: "Orders", version: nil, build: nil, device: "Mac", system: "macOS 27.0")
            let expectedFull = "Orders, version 1.4.2 (88), iPad, iOS 27.2"
            let expectedBare = "Orders, Mac, macOS 27.0"

            let actualFull = full.spoken
            let actualBare = bare.spoken

            #expect(actualFull == expectedFull)
            #expect(actualBare == expectedBare)
        }

        @Test("The navigator has All, then a tab per category in the drawer's order, General last, marked unread when a plugin in it has a badge")
        func tabs() {
            let plugins = [
                AnyDebugDrawerPlugin(TabPlugin(title: "Cookies", category: "Storage")),
                AnyDebugDrawerPlugin(TabPlugin(title: "Misc", category: "General")),
                AnyDebugDrawerPlugin(TabPlugin(title: "App Info", category: "App")),
                AnyDebugDrawerPlugin(TabPlugin(title: "Keychain", category: "Storage"))
            ]
            let badges = ["Keychain": 2]
            let expectedTitles = ["All", "App", "Storage", "General"]
            let expectedUnread = [true, false, true, false]

            let actual = DrawerNavigatorTab.tabs(for: plugins, badges: badges)

            #expect(actual.map(\.title) == expectedTitles)
            #expect(actual.map(\.hasUnread) == expectedUnread)
        }
    }

    private struct TabPlugin: DebugDrawerPlugin {
        let title: String
        let category: String
        var icon = "circle"
        nonisolated var id: String { title }
        var body: some View { EmptyView() }
    }
#endif
