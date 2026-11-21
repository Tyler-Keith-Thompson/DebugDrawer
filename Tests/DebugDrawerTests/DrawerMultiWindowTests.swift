#if DEBUG
    #if os(macOS)
        import AppKit
    #endif
    @testable import DebugDrawer
    import DebugDrawerTestSupport
    import SwiftUI
    import Testing

    // The rules the Mac and iOS share: which window's drawer toggle() acts on, and which window's
    // drawer lists a local plugin. The SwiftPM and Bazel runners connect no UIWindowScene, so on
    // iOS these are the tests of those rules; the Mac also runs them on real windows below. Each
    // test that registers makes a drawer of its own over a UserDefaults suite named for the test,
    // removed when the test ends.
    @MainActor
    @Suite("Multiple windows")
    struct DrawerMultiWindowTests {
        @Test("toggle() acts on the drawer of the key window (on iOS, the foreground-active scene), not the last one attached")
        func frontWindowWins() {
            let first = DrawerPresentation()
            let second = DrawerPresentation()
            first.scope = ObjectIdentifier(first)
            second.scope = ObjectIdentifier(second)
            let front = [ObjectIdentifier(first)]

            let actual = DebugDrawer.frontPresentation(of: [first, second], front: front)

            #expect(actual === first)
        }

        @Test("toggle() acts on the first window in front that has a drawer, skipping one with none")
        func firstAttachedFrontWindowWins() {
            let first = DrawerPresentation()
            let second = DrawerPresentation()
            let unattached = DrawerPresentation()
            first.scope = ObjectIdentifier(first)
            second.scope = ObjectIdentifier(second)
            let front = [ObjectIdentifier(unattached), ObjectIdentifier(second), ObjectIdentifier(first)]

            let actual = DebugDrawer.frontPresentation(of: [first, second], front: front)

            #expect(actual === second)
        }

        @Test("With no attached window in front, toggle() acts on the last window attached")
        func lastAttachedWithoutFront() {
            let first = DrawerPresentation()
            let second = DrawerPresentation()
            first.scope = ObjectIdentifier(first)
            second.scope = ObjectIdentifier(second)

            let actual = DebugDrawer.frontPresentation(of: [first, second], front: [])

            #expect(actual === second)
        }

        @Test("With no window attached, toggle() has no window's drawer to act on")
        func noneAttached() {
            let actual = DebugDrawer.frontPresentation(of: [], front: [])

            #expect(actual == nil)
        }

        @Test("A local plugin registered from one window is listed in that window's drawer only; one from no window in every drawer")
        func localPluginsBelongToTheirWindow() throws {
            let suite = temporarySuiteName("DrawerMultiWindowTests.\(#function)")
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let sut = DebugDrawer(defaults: defaults)
            let first = ObjectIdentifier(DrawerPresentation.self)
            let second = ObjectIdentifier(DrawerLocalRegistration.self)
            _ = sut.registerLocal(WindowPlugin(id: "multi-window.first"), scope: first)
            _ = sut.registerLocal(WindowPlugin(id: "multi-window.second"), scope: second)
            sut.registerLocal(WindowPlugin(id: "multi-window.everywhere"))
            let expectedFirst = ["multi-window.first", "multi-window.everywhere"]
            let expectedSecond = ["multi-window.second", "multi-window.everywhere"]

            let actualFirst = sut.localPlugins(listedIn: first).map(\.id).filter { $0.hasPrefix("multi-window.") }
            let actualSecond = sut.localPlugins(listedIn: second).map(\.id).filter { $0.hasPrefix("multi-window.") }

            #expect(actualFirst == expectedFirst)
            #expect(actualSecond == expectedSecond)
        }

        @Test("The same plugin registered from two windows stays in each window's drawer until that window's view leaves")
        func samePluginInTwoWindows() throws {
            let suite = temporarySuiteName("DrawerMultiWindowTests.\(#function)")
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let sut = DebugDrawer(defaults: defaults)
            let first = ObjectIdentifier(DrawerPresentation.self)
            let second = ObjectIdentifier(DrawerLocalRegistration.self)
            let firstToken = sut.registerLocal(WindowPlugin(id: "multi-window.shared", title: "First"), scope: first)
            _ = sut.registerLocal(WindowPlugin(id: "multi-window.shared", title: "Second"), scope: second)

            sut.unregisterLocal(id: "multi-window.shared", token: firstToken)

            let actualFirst = sut.localPlugins(listedIn: first).filter { $0.id == "multi-window.shared" }.map(\.title)
            let actualSecond = sut.localPlugins(listedIn: second).filter { $0.id == "multi-window.shared" }.map(\.title)
            #expect(actualFirst.isEmpty)
            #expect(actualSecond == ["Second"])
        }

        @Test("A plugin registered before its view knows its window moves to that window's drawer once it does")
        func registrationMovesToItsWindow() throws {
            let suite = temporarySuiteName("DrawerMultiWindowTests.\(#function)")
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let sut = DebugDrawer(defaults: defaults)
            let first = ObjectIdentifier(DrawerPresentation.self)
            let second = ObjectIdentifier(DrawerLocalRegistration.self)
            let token = sut.registerLocal(WindowPlugin(id: "multi-window.moving"), scope: nil)

            sut.moveLocal(token: token, to: first)

            #expect(sut.localPlugins(listedIn: first).contains { $0.id == "multi-window.moving" })
            #expect(!sut.localPlugins(listedIn: second).contains { $0.id == "multi-window.moving" })
        }

        @Test("The detached drawer, the one tvOS, visionOS and watchOS draw, lists every window's local plugins")
        func detachedDrawerListsEveryLocalPlugin() throws {
            let suite = temporarySuiteName("DrawerMultiWindowTests.\(#function)")
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let sut = DebugDrawer(defaults: defaults)
            let first = ObjectIdentifier(DrawerPresentation.self)
            _ = sut.registerLocal(WindowPlugin(id: "multi-window.detached"), scope: first)

            let actual = sut.localPlugins(listedIn: nil).contains { $0.id == "multi-window.detached" }

            #expect(actual)
        }
    }

    /// A plugin with the ID the test gives it.
    private struct WindowPlugin: DebugDrawerPlugin {
        let id: String
        var title = "Window"
        let icon = "macwindow"
        var body: some View { Text(title) }
    }

    #if os(macOS)
        // Real windows, borderless and far off screen: ordered in, so they can be key, but never seen.
        // Each test makes a drawer of its own over a UserDefaults suite named for the test, removed
        // when the test ends. The tests are synchronous on the main actor, so none runs between
        // another's making a window key and its toggle.
        @MainActor
        @Suite("Multiple windows on the Mac")
        struct DrawerMultiWindowMacTests {
            @Test("With two windows open, toggle() opens the drawer only in the key window, or in the frontmost while the app is inactive")
            func toggleOpensOnlyTheKeyWindow() throws {
                let suite = temporarySuiteName("DrawerMultiWindowMacTests.\(#function)")
                let defaults = try #require(UserDefaults(suiteName: suite))
                defer { defaults.removePersistentDomain(forName: suite) }
                let sut = DebugDrawer(defaults: defaults)
                let first = KeyableWindow(contentRect: CGRect(x: -30000, y: -30000, width: 900, height: 600))
                let second = KeyableWindow(contentRect: CGRect(x: -31000, y: -30000, width: 900, height: 600))
                defer { [first, second].forEach { $0.close() } }
                sut.attach(to: first)
                sut.attach(to: second)
                let firstDrawer = try #require(sut.attachments.first { $0.window === first })
                let secondDrawer = try #require(sut.attachments.first { $0.window === second })
                // The test runner isn't the active app, so it has no key window: the window in front
                // stands in for it, as it does for an app the user has switched away from. The
                // order of the key window first is the shared rule's, tested above.
                first.makeKeyAndOrderFront(nil)
                defer {
                    firstDrawer.presentation.isOpen = false
                    secondDrawer.presentation.isOpen = false
                }

                sut.toggle()

                #expect(firstDrawer.presentation.isOpen)
                #expect(firstDrawer.panel.isVisible)
                #expect(!secondDrawer.presentation.isOpen)
                #expect(!secondDrawer.panel.isVisible)
                #expect(sut.isOpen)
            }

            @Test("toggle(in:) opens the drawer in the window given and leaves the key window's closed")
            func toggleInOpensTheGivenWindow() throws {
                let suite = temporarySuiteName("DrawerMultiWindowMacTests.\(#function)")
                let defaults = try #require(UserDefaults(suiteName: suite))
                defer { defaults.removePersistentDomain(forName: suite) }
                let sut = DebugDrawer(defaults: defaults)
                let first = KeyableWindow(contentRect: CGRect(x: -30000, y: -30000, width: 900, height: 600))
                let second = KeyableWindow(contentRect: CGRect(x: -31000, y: -30000, width: 900, height: 600))
                defer { [first, second].forEach { $0.close() } }
                sut.attach(to: first)
                sut.attach(to: second)
                let firstDrawer = try #require(sut.attachments.first { $0.window === first })
                let secondDrawer = try #require(sut.attachments.first { $0.window === second })
                // The test runner isn't the active app, so it has no key window: the window in front
                // stands in for it, as it does for an app the user has switched away from. The
                // order of the key window first is the shared rule's, tested above.
                first.makeKeyAndOrderFront(nil)
                defer {
                    firstDrawer.presentation.isOpen = false
                    secondDrawer.presentation.isOpen = false
                }

                sut.toggle(in: second)

                #expect(secondDrawer.presentation.isOpen)
                #expect(secondDrawer.panel.isVisible)
                #expect(!firstDrawer.presentation.isOpen)
                #expect(!firstDrawer.panel.isVisible)
            }

            @Test("toggle(in:) closes the drawer it opened in that window")
            func toggleInTwiceCloses() throws {
                let suite = temporarySuiteName("DrawerMultiWindowMacTests.\(#function)")
                let defaults = try #require(UserDefaults(suiteName: suite))
                defer { defaults.removePersistentDomain(forName: suite) }
                let sut = DebugDrawer(defaults: defaults)
                let window = KeyableWindow(contentRect: CGRect(x: -30000, y: -30000, width: 900, height: 600))
                defer { window.close() }
                sut.attach(to: window)
                let drawer = try #require(sut.attachments.first { $0.window === window })

                sut.toggle(in: window)
                sut.toggle(in: window)

                #expect(!drawer.presentation.isOpen)
            }

            @Test("toggle(in:) attaches a window not attached yet and opens the drawer in it")
            func toggleInAttaches() throws {
                let suite = temporarySuiteName("DrawerMultiWindowMacTests.\(#function)")
                let defaults = try #require(UserDefaults(suiteName: suite))
                defer { defaults.removePersistentDomain(forName: suite) }
                let sut = DebugDrawer(defaults: defaults)
                let window = KeyableWindow(contentRect: CGRect(x: -30000, y: -30000, width: 900, height: 600))
                defer { window.close() }
                #expect(!sut.attachments.contains { $0.window === window })

                sut.toggle(in: window)

                let drawer = try #require(sut.attachments.first { $0.window === window })
                defer { drawer.presentation.isOpen = false }
                #expect(drawer.presentation.isOpen)
                #expect(drawer.panel.parent === window)
                #expect(drawer.panel.isVisible)
            }
        }

        // debugLocalPlugin(_:) and debugDrawer() register with and show the shared drawer, so these
        // tests stay on it, in the serialized suite of the shared drawer's tests.
        extension SharedDrawerTests {
            @MainActor
            @Suite("Multiple windows on the Mac, from SwiftUI views")
            struct SharedDrawerMultiWindowMacTests {
                @Test("Local plugins appear only in the drawer of the window whose views registered them; global plugins in both")
                func localPluginsStayInTheirWindow() throws {
                    DebugDrawer.shared.registerGlobal(WindowPlugin(id: "multi-window-mac.global"))
                    defer { DebugDrawer.shared.unregisterGlobal(id: "multi-window-mac.global") }
                    let first = KeyableWindow(contentRect: CGRect(x: -30000, y: -30000, width: 900, height: 600))
                    let second = KeyableWindow(contentRect: CGRect(x: -31000, y: -30000, width: 900, height: 600))
                    let firstHost = NSHostingView(rootView: Text("First")
                        .debugLocalPlugin(WindowPlugin(id: "multi-window-mac.first"))
                        .debugDrawer())
                    let secondHost = NSHostingView(rootView: Text("Second")
                        .debugLocalPlugin(WindowPlugin(id: "multi-window-mac.second"))
                        .debugDrawer())
                    first.contentView = firstHost
                    second.contentView = secondHost
                    firstHost.layoutSubtreeIfNeeded()
                    secondHost.layoutSubtreeIfNeeded()
                    defer { [first, second].forEach { $0.close() } }
                    let firstDrawer = try #require(DebugDrawer.shared.attachments.first { $0.window === first })
                    let secondDrawer = try #require(DebugDrawer.shared.attachments.first { $0.window === second })
                    let expectedFirst = ["multi-window-mac.first", "multi-window-mac.global"]
                    let expectedSecond = ["multi-window-mac.second", "multi-window-mac.global"]

                    let actualFirst = DebugDrawerOverlay(drawer: .shared, presentation: firstDrawer.presentation)
                        .allPlugins.map(\.id).filter { $0.hasPrefix("multi-window-mac.") }
                    let actualSecond = DebugDrawerOverlay(drawer: .shared, presentation: secondDrawer.presentation)
                        .allPlugins.map(\.id).filter { $0.hasPrefix("multi-window-mac.") }

                    #expect(actualFirst == expectedFirst)
                    #expect(actualSecond == expectedSecond)
                }

                @Test("Closing a window forgets the local plugins its views registered")
                func closingForgetsLocalPlugins() throws {
                    let window = KeyableWindow(contentRect: CGRect(x: -30000, y: -30000, width: 900, height: 600))
                    let host = NSHostingView(rootView: Text("Window")
                        .debugLocalPlugin(WindowPlugin(id: "multi-window-mac.closing"))
                        .debugDrawer())
                    window.contentView = host
                    host.layoutSubtreeIfNeeded()
                    try #require(DebugDrawer.shared.localPlugins.contains { $0.id == "multi-window-mac.closing" })

                    window.close()

                    #expect(!DebugDrawer.shared.localPlugins.contains { $0.id == "multi-window-mac.closing" })
                }
            }
        }

        /// A borderless window that can be key, ordered in when made.
        private final class KeyableWindow: NSWindow {
            init(contentRect: CGRect) {
                super.init(contentRect: contentRect, styleMask: .borderless, backing: .buffered, defer: false)
                isReleasedWhenClosed = false
                orderFront(nil)
            }

            override var canBecomeKey: Bool {
                true
            }

            override var canBecomeMain: Bool {
                true
            }
        }
    #endif
#endif
