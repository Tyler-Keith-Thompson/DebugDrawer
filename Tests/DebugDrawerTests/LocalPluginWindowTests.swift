#if DEBUG
    #if os(macOS)
        import AppKit
    #elseif os(iOS) || os(visionOS)
        import UIKit
    #endif
    @testable import DebugDrawer
    import SwiftUI
    import Testing

    #if os(macOS)
        // Real windows, borderless and far off screen: ordered in, so the drawer's panels can be,
        // but never seen. Each test makes a drawer of its own over a UserDefaults suite named for
        // the test, removed when the test ends.
        @MainActor
        @Suite("Local plugins registered for an NSWindow")
        struct LocalPluginNSWindowTests {
            @Test("registerLocal(_:in:) lists the plugin only in that window's drawer; global plugins in both")
            func listedOnlyInItsWindow() throws {
                let suite = "LocalPluginNSWindowTests.\(#function).\(UUID().uuidString)"
                let defaults = try #require(UserDefaults(suiteName: suite))
                defer { defaults.removePersistentDomain(forName: suite) }
                let sut = DebugDrawer(defaults: defaults)
                sut.registerGlobal(WindowLocalPlugin(id: "window-local.global"))
                let first = OffscreenWindow(left: -30000)
                let second = OffscreenWindow(left: -31000)
                defer { [first, second].forEach { $0.close() } }
                sut.attach(to: first)
                sut.attach(to: second)
                let firstDrawer = try #require(sut.attachments.first { $0.window === first })
                let secondDrawer = try #require(sut.attachments.first { $0.window === second })
                let expectedFirst = ["window-local.first", "window-local.global"]
                let expectedSecond = ["window-local.global"]

                sut.registerLocal(WindowLocalPlugin(id: "window-local.first"), in: first)

                let actualFirst = DebugDrawerOverlay(drawer: sut, presentation: firstDrawer.presentation)
                    .allPlugins.map(\.id).filter { $0.hasPrefix("window-local.") }
                let actualSecond = DebugDrawerOverlay(drawer: sut, presentation: secondDrawer.presentation)
                    .allPlugins.map(\.id).filter { $0.hasPrefix("window-local.") }
                #expect(actualFirst == expectedFirst)
                #expect(actualSecond == expectedSecond)
            }

            @Test("A sheet's window registers the plugin for the window the sheet is on")
            func sheetRegistersForItsParent() throws {
                let parent = OffscreenWindow(left: -30000, styleMask: .titled)
                let sheet = OffscreenWindow(left: -30000, styleMask: .titled)
                parent.beginSheet(sheet)
                defer {
                    parent.endSheet(sheet)
                    [sheet, parent].forEach { $0.close() }
                }
                try #require(sheet.sheetParent === parent)
                let suite = "LocalPluginNSWindowTests.\(#function).\(UUID().uuidString)"
                let defaults = try #require(UserDefaults(suiteName: suite))
                defer { defaults.removePersistentDomain(forName: suite) }
                let sut = DebugDrawer(defaults: defaults)
                let expected = ["window-local.sheet"]

                sut.registerLocal(WindowLocalPlugin(id: "window-local.sheet"), in: sheet)

                let actual = sut.localPlugins(listedIn: ObjectIdentifier(parent)).map(\.id)
                #expect(actual == expected)
                #expect(sut.localPlugins(listedIn: ObjectIdentifier(sheet)).isEmpty)
            }

            @Test("Closing a window removes the plugins registered for it, attached or not, and leaves another window's")
            func closingRemovesItsRegistrations() throws {
                let closing = OffscreenWindow(left: -30000)
                let staying = OffscreenWindow(left: -31000)
                defer { staying.close() }
                // A drawer of its own that no window is attached to, so only registerLocal(_:in:)'s
                // own watch on the window can remove the plugins.
                let suite = "LocalPluginNSWindowTests.\(#function).\(UUID().uuidString)"
                let defaults = try #require(UserDefaults(suiteName: suite))
                defer { defaults.removePersistentDomain(forName: suite) }
                let sut = DebugDrawer(defaults: defaults)
                sut.registerLocal(WindowLocalPlugin(id: "window-local.closing.one"), in: closing)
                sut.registerLocal(WindowLocalPlugin(id: "window-local.closing.two"), in: closing)
                sut.registerLocal(WindowLocalPlugin(id: "window-local.staying"), in: staying)
                try #require(sut.localPlugins.count == 3)
                let expected = ["window-local.staying"]

                closing.close()

                let actual = sut.localPlugins.map(\.id)
                #expect(actual == expected)
                #expect(sut.localScopeObservers[ObjectIdentifier(closing)] == nil)
            }

            @Test("unregisterLocal(id:token:) removes a plugin registered for a window before the window closes")
            func unregisterBeforeClosing() throws {
                let window = OffscreenWindow(left: -30000)
                defer { window.close() }
                let suite = "LocalPluginNSWindowTests.\(#function).\(UUID().uuidString)"
                let defaults = try #require(UserDefaults(suiteName: suite))
                defer { defaults.removePersistentDomain(forName: suite) }
                let sut = DebugDrawer(defaults: defaults)
                let token = sut.registerLocal(WindowLocalPlugin(id: "window-local.unregister"), in: window)

                sut.unregisterLocal(id: "window-local.unregister", token: token)

                #expect(sut.localPlugins.isEmpty)
            }
        }

        /// A borderless window far off screen, ordered in when made, so a drawer's panel can be
        /// but is never seen; kept after closing, so a test can still read it.
        private final class OffscreenWindow: NSWindow {
            init(left: CGFloat, styleMask: NSWindow.StyleMask = .borderless) {
                super.init(contentRect: CGRect(x: left, y: -30000, width: 900, height: 600), styleMask: styleMask, backing: .buffered, defer: false)
                isReleasedWhenClosed = false
                orderFront(nil)
            }
        }
    #endif

    #if os(iOS) || os(visionOS)
        // The SwiftPM and Bazel runners are the xctest tool, which connects no scene and supports no
        // second one, and UIScene's initializer needs a session nothing public makes. So these tests
        // stand an object in for each scene and post UIScene.didDisconnectNotification for it, through
        // the registration registerLocal(_:in: UIWindowScene) makes with its scene's identifier.
        @MainActor
        @Suite("Local plugins registered for a UIWindowScene")
        struct LocalPluginWindowSceneTests {
            @Test("A plugin registered for one scene is listed only in that scene's drawer; global plugins in both")
            func listedOnlyInItsScene() throws {
                let first = NSObject()
                let second = NSObject()
                let suite = "LocalPluginWindowSceneTests.\(#function).\(UUID().uuidString)"
                let defaults = try #require(UserDefaults(suiteName: suite))
                defer { defaults.removePersistentDomain(forName: suite) }
                let sut = DebugDrawer(defaults: defaults)
                sut.registerGlobal(WindowLocalPlugin(id: "scene-local.global"))
                let firstDrawer = DrawerPresentation()
                let secondDrawer = DrawerPresentation()
                firstDrawer.scope = ObjectIdentifier(first)
                secondDrawer.scope = ObjectIdentifier(second)
                let expectedFirst = ["scene-local.first", "scene-local.global"]
                let expectedSecond = ["scene-local.global"]

                sut.registerLocal(
                    WindowLocalPlugin(id: "scene-local.first"),
                    scope: ObjectIdentifier(first), until: UIScene.didDisconnectNotification, from: first
                )

                let actualFirst = DebugDrawerOverlay(drawer: sut, presentation: firstDrawer).allPlugins.map(\.id)
                let actualSecond = DebugDrawerOverlay(drawer: sut, presentation: secondDrawer).allPlugins.map(\.id)
                #expect(actualFirst == expectedFirst)
                #expect(actualSecond == expectedSecond)
            }

            @Test("Disconnecting a scene removes the plugins registered for it and leaves another scene's")
            func disconnectingRemovesItsRegistrations() throws {
                let disconnecting = NSObject()
                let staying = NSObject()
                let suite = "LocalPluginWindowSceneTests.\(#function).\(UUID().uuidString)"
                let defaults = try #require(UserDefaults(suiteName: suite))
                defer { defaults.removePersistentDomain(forName: suite) }
                let sut = DebugDrawer(defaults: defaults)
                let registrations = [
                    ("scene-local.disconnecting.one", disconnecting),
                    ("scene-local.disconnecting.two", disconnecting),
                    ("scene-local.staying", staying)
                ]
                for (id, scene) in registrations {
                    sut.registerLocal(
                        WindowLocalPlugin(id: id),
                        scope: ObjectIdentifier(scene), until: UIScene.didDisconnectNotification, from: scene
                    )
                }
                try #require(sut.localPlugins.count == 3)
                let expected = ["scene-local.staying"]

                NotificationCenter.default.post(name: UIScene.didDisconnectNotification, object: disconnecting)

                let actual = sut.localPlugins.map(\.id)
                #expect(actual == expected)
                #expect(sut.localScopeObservers[ObjectIdentifier(disconnecting)] == nil)
            }
        }
    #endif

    #if os(macOS) || os(iOS) || os(visionOS)
        /// A plugin with the ID the test gives it.
        private struct WindowLocalPlugin: DebugDrawerPlugin {
            let id: String
            var title = "Window"
            let icon = "macwindow"
            var body: some View { Text(title) }
        }
    #endif
#endif
