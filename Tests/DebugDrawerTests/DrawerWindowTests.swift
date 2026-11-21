// The drawer's windows are AppKit's and UIKit's.
#if os(macOS)
    import AppKit
    @testable import DebugDrawer
    import SwiftUI
    import Testing

    // Each test that attaches a window makes a drawer of its own over a UserDefaults suite named
    // for the test, removed when the test ends.
    @MainActor
    @Suite("Drawer window")
    struct DrawerWindowTests {
        @Test("Opening a window's drawer orders its panel in above that window, as a child window at its trailing edge")
        func panelIsAChildAboveTheWindow() throws {
            let suite = "DrawerWindowTests.\(#function).\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let drawer = DebugDrawer(defaults: defaults)
            // Borderless and far off screen: ordered in, so the panel can be, but never seen.
            let window = NSWindow(
                contentRect: CGRect(x: -30000, y: -30000, width: 900, height: 600),
                styleMask: .borderless, backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            window.orderFront(nil)
            defer { window.close() }
            drawer.attach(to: window)
            let attachment = try #require(drawer.attachments.first { $0.window === window })
            let expectedFrame = CGRect(x: -30000 + 900 - 8 - 316, y: -30000 + 8, width: 316, height: 600 - 16)

            attachment.presentation.isOpen = true

            let panel = attachment.panel
            #expect(panel.parent === window)
            #expect(window.childWindows?.contains(panel) == true)
            #expect(panel.isVisible)
            let frontToBack = (NSWindow.windowNumbers(options: []) ?? []).map(\.intValue)
            let panelIndex = try #require(frontToBack.firstIndex(of: panel.windowNumber))
            let windowIndex = try #require(frontToBack.firstIndex(of: window.windowNumber))
            #expect(panelIndex < windowIndex)
            #expect(panel.level.rawValue >= window.level.rawValue)
            #expect(panel.frame == expectedFrame)
        }

        @Test("Attaching a window twice keeps one drawer for it")
        func attachingTwiceKeepsOneDrawer() throws {
            let suite = "DrawerWindowTests.\(#function).\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let drawer = DebugDrawer(defaults: defaults)
            let window = NSWindow(
                contentRect: CGRect(x: -30000, y: -30000, width: 900, height: 600),
                styleMask: .borderless, backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            defer { window.close() }

            drawer.attach(to: window)
            drawer.attach(to: window)

            let actual = drawer.attachments.filter { $0.window === window }.count
            #expect(actual == 1)
        }

        @Test("A drawer opened before its window is on screen comes on screen with the window")
        func panelComesInWithItsWindow() throws {
            let suite = "DrawerWindowTests.\(#function).\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let drawer = DebugDrawer(defaults: defaults)
            let window = NSWindow(
                contentRect: CGRect(x: -30000, y: -30000, width: 900, height: 600),
                styleMask: .borderless, backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            defer { window.close() }
            drawer.attach(to: window)
            let attachment = try #require(drawer.attachments.first { $0.window === window })
            attachment.presentation.isOpen = true

            window.orderFront(nil)

            #expect(attachment.panel.parent === window)
            #expect(attachment.panel.isVisible)
            attachment.presentation.isOpen = false
        }

        @Test("Opening one window's drawer leaves another window's drawer closed")
        func eachWindowHasItsOwnDrawer() throws {
            let suite = "DrawerWindowTests.\(#function).\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let drawer = DebugDrawer(defaults: defaults)
            let first = NSWindow(
                contentRect: CGRect(x: -30000, y: -30000, width: 900, height: 600),
                styleMask: .borderless, backing: .buffered, defer: false
            )
            let second = NSWindow(
                contentRect: CGRect(x: -31000, y: -30000, width: 900, height: 600),
                styleMask: .borderless, backing: .buffered, defer: false
            )
            for window in [first, second] {
                window.isReleasedWhenClosed = false
                window.orderFront(nil)
            }
            defer { [first, second].forEach { $0.close() } }
            drawer.attach(to: first)
            drawer.attach(to: second)
            let firstDrawer = try #require(drawer.attachments.first { $0.window === first })
            let secondDrawer = try #require(drawer.attachments.first { $0.window === second })

            firstDrawer.presentation.isOpen = true

            #expect(firstDrawer.presentation.isOpen)
            #expect(firstDrawer.panel.isVisible)
            #expect(!secondDrawer.presentation.isOpen)
            #expect(!secondDrawer.panel.isVisible)
        }

        @Test("A drawer opened before any window is attached opens in the first window attached")
        func theFirstWindowTakesTheDetachedState() throws {
            let suite = "DrawerWindowTests.\(#function).\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let drawer = DebugDrawer(defaults: defaults)
            drawer.detachedPresentation.isOpen = true
            let window = NSWindow(
                contentRect: CGRect(x: -30000, y: -30000, width: 900, height: 600),
                styleMask: .borderless, backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            window.orderFront(nil)
            defer { window.close() }

            drawer.attach(to: window)

            let attachment = try #require(drawer.attachments.first { $0.window === window })
            #expect(attachment.presentation.isOpen)
            #expect(attachment.panel.isVisible)
            #expect(!drawer.detachedPresentation.isOpen)
        }

        @Test("Closing a window detaches it from the drawer that attached it and takes its panel off screen")
        func closingTheWindowDetaches() throws {
            let suite = "DrawerWindowTests.\(#function).\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let drawer = DebugDrawer(defaults: defaults)
            let window = NSWindow(
                contentRect: CGRect(x: -30000, y: -30000, width: 900, height: 600),
                styleMask: .borderless, backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            window.orderFront(nil)
            drawer.attach(to: window)
            let attachment = try #require(drawer.attachments.first { $0.window === window })
            attachment.presentation.isOpen = true

            window.close()

            #expect(!drawer.attachments.contains { $0.presentation === attachment.presentation })
            #expect(!attachment.panel.isVisible)
        }

        @Test("The panel rises over sheets and app-modal alerts only while its window is the active app's main window")
        func panelLevel() {
            let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)

            let active = DrawerChildPanel.level(appIsActive: true, hostIsMain: true, host: window)
            let inactive = DrawerChildPanel.level(appIsActive: false, hostIsMain: true, host: window)
            let notMain = DrawerChildPanel.level(appIsActive: true, hostIsMain: false, host: window)

            #expect(active.rawValue > NSWindow.Level.modalPanel.rawValue)
            #expect(inactive == window.level)
            #expect(notMain == window.level)
        }

        @Test("A regular panel sits at the content's trailing edge, 316 points wide, inside an 8 point margin")
        func regularFrame() {
            let content = CGRect(x: 100, y: 50, width: 1000, height: 700)
            let expected = CGRect(x: 100 + 1000 - 8 - 316, y: 58, width: 316, height: 684)

            let actual = DrawerChildPanel.frame(in: content, layout: .regular)

            #expect(actual == expected)
        }

        @Test("A compact panel spans the content's width, inside an 8 point margin")
        func compactFrame() {
            let content = CGRect(x: 100, y: 50, width: 500, height: 700)
            let expected = CGRect(x: 108, y: 58, width: 484, height: 684)

            let actual = DrawerChildPanel.frame(in: content, layout: .compact)

            #expect(actual == expected)
        }

        @Test("A sheet's window attaches the window it is on")
        func sheetAttachesItsParent() {
            let window = NSWindow(
                contentRect: CGRect(x: -30000, y: -30000, width: 900, height: 600),
                styleMask: .borderless, backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            window.orderFront(nil)
            defer { window.close() }
            let sheet = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 300, height: 200), styleMask: .titled, backing: .buffered, defer: false)
            window.beginSheet(sheet)
            defer { window.endSheet(sheet) }

            let actual = DebugDrawer.appWindow(for: sheet)

            #expect(actual === window)
        }
    }

    // debugDrawer() shows the shared drawer, so these tests stay on it, in the serialized suite of
    // the shared drawer's tests, as does the one that reads the shared drawer as another drawer's
    // window closes.
    extension SharedDrawerTests {
        @MainActor
        @Suite("Drawer window on the shared drawer")
        struct SharedDrawerWindowTests {
            @Test("Opening the drawer from the app updates the app's views with no animation")
            func openingAnimatesNoAppView() throws {
                let recorder = AnimationRecorder()
                let window = NSWindow(
                    contentRect: CGRect(x: -30000, y: -30000, width: 900, height: 600),
                    styleMask: .borderless, backing: .buffered, defer: false
                )
                window.isReleasedWhenClosed = false
                let host = NSHostingView(rootView: AnimationProbe(drawer: .shared, recorder: recorder).debugDrawer())
                window.contentView = host
                window.orderFront(nil)
                defer { window.close() }
                host.layoutSubtreeIfNeeded()
                let attachment = try #require(DebugDrawer.shared.attachments.first { $0.window === window })
                recorder.updates = []

                DebugDrawer.shared.toggle()
                host.layoutSubtreeIfNeeded()
                let opened = attachment.presentation.isOpen
                attachment.presentation.isOpen = false
                host.layoutSubtreeIfNeeded()

                #expect(opened)
                #expect(!recorder.updates.isEmpty)
                #expect(recorder.updates.allSatisfy { !$0 })
            }

            @Test("A debugDrawer() window and an AppKit window attached with attach(to:) get the same drawer: one panel view, one size")
            func bothEntryPointsShareOnePresentation() throws {
                let swiftUIWindow = NSWindow(
                    contentRect: CGRect(x: -30000, y: -30000, width: 900, height: 600),
                    styleMask: .borderless, backing: .buffered, defer: false
                )
                let appKitWindow = NSWindow(
                    contentRect: CGRect(x: -31000, y: -30000, width: 900, height: 600),
                    styleMask: .borderless, backing: .buffered, defer: false
                )
                let host = NSHostingView(rootView: Text("SwiftUI").debugDrawer())
                swiftUIWindow.contentView = host
                appKitWindow.contentView = NSTextField(labelWithString: "AppKit")
                for window in [swiftUIWindow, appKitWindow] {
                    window.isReleasedWhenClosed = false
                    window.orderFront(nil)
                }
                defer { [swiftUIWindow, appKitWindow].forEach { $0.close() } }
                host.layoutSubtreeIfNeeded()
                DebugDrawer.shared.attach(to: appKitWindow)
                let swiftUIDrawer = try #require(DebugDrawer.shared.attachments.first { $0.window === swiftUIWindow })
                let appKitDrawer = try #require(DebugDrawer.shared.attachments.first { $0.window === appKitWindow })

                swiftUIDrawer.presentation.isOpen = true
                appKitDrawer.presentation.isOpen = true
                defer {
                    swiftUIDrawer.presentation.isOpen = false
                    appKitDrawer.presentation.isOpen = false
                }

                let swiftUIContent = try #require(swiftUIDrawer.panel.contentView)
                let appKitContent = try #require(appKitDrawer.panel.contentView)
                #expect(type(of: swiftUIContent) == type(of: appKitContent))
                #expect(swiftUIDrawer.panel.parent === swiftUIWindow)
                #expect(appKitDrawer.panel.parent === appKitWindow)
                #expect(swiftUIDrawer.panel.isVisible)
                #expect(appKitDrawer.panel.isVisible)
                #expect(swiftUIDrawer.panel.frame.size == appKitDrawer.panel.frame.size)
            }

            @Test("Closing a window another drawer attached leaves the shared drawer's attachments and that window's local plugins as they were")
            func closingAnotherDrawersWindowLeavesTheSharedDrawer() throws {
                let suite = "DrawerWindowTests.\(#function).\(UUID().uuidString)"
                let defaults = try #require(UserDefaults(suiteName: suite))
                defer { defaults.removePersistentDomain(forName: suite) }
                let drawer = DebugDrawer(defaults: defaults)
                let sharedWindow = NSWindow(
                    contentRect: CGRect(x: -30000, y: -30000, width: 900, height: 600),
                    styleMask: .borderless, backing: .buffered, defer: false
                )
                let window = NSWindow(
                    contentRect: CGRect(x: -31000, y: -30000, width: 900, height: 600),
                    styleMask: .borderless, backing: .buffered, defer: false
                )
                for each in [sharedWindow, window] {
                    each.isReleasedWhenClosed = false
                    each.orderFront(nil)
                }
                defer { sharedWindow.close() }
                DebugDrawer.shared.attach(to: sharedWindow)
                // As debugLocalPlugin(_:) registers it for a view in the window, with no close observer.
                let token = DebugDrawer.shared.registerLocal(ClosingWindowPlugin(), scope: DebugDrawer.scope(of: window))
                defer { DebugDrawer.shared.unregisterLocal(id: ClosingWindowPlugin().id, token: token) }
                drawer.attach(to: window)
                let expected = DebugDrawer.shared.attachments.map { ObjectIdentifier($0.presentation) }

                window.close()

                let actual = DebugDrawer.shared.attachments.map { ObjectIdentifier($0.presentation) }
                #expect(actual == expected)
                #expect(DebugDrawer.shared.localRegistrations.contains { $0.token == token })
            }
        }
    }

    /// A local plugin of the window that closes.
    private struct ClosingWindowPlugin: DebugDrawerPlugin {
        let title = "Closing Window"
        let icon = "macwindow"
        var body: some View { Text(title) }
    }

    /// Whether each update of the probe ran in an animated transaction.
    @MainActor
    private final class AnimationRecorder {
        var updates: [Bool] = []
    }

    /// An app view that reads the drawer, so it updates whenever the drawer opens or closes, and
    /// records whether that update was animated.
    private struct AnimationProbe: View {
        @ObservedObject var drawer: DebugDrawer
        let recorder: AnimationRecorder

        var body: some View {
            Text(drawer.isOpen ? "Open" : "Closed")
                .frame(width: 900, height: 600)
                .transaction { transaction in
                    recorder.updates.append(transaction.animation != nil)
                }
        }
    }
// UIKit can't make a window in xctest, which runs package tests on Mac Catalyst without an
// NSApplication, so the iOS tests run on the iOS simulator alone.
#elseif os(iOS) && !targetEnvironment(macCatalyst)
    @testable import DebugDrawer
    import SwiftUI
    import Testing
    import UIKit

    // The SwiftPM test runner connects no window scene, so these tests use the drawer's window on
    // its own, as attach(to:) makes it for a scene.
    @MainActor
    @Suite("Drawer window")
    struct DrawerWindowTests {
        @Test("Opening the drawer shows its window, above the level alerts are presented at; closing hides it")
        func windowIsAboveAlerts() throws {
            let suite = "DrawerWindowTests.\(#function).\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let drawer = DebugDrawer(defaults: defaults)
            let presentation = DrawerPresentation()
            let sut = DrawerSceneWindow(scene: nil, drawer: drawer, presentation: presentation)

            presentation.isOpen = true
            let shownWhileOpen = !sut.isHidden
            presentation.isOpen = false
            sut.drawerDidHide()

            #expect(shownWhileOpen)
            #expect(sut.windowLevel > .alert)
            #expect(sut.isHidden)
        }

        @Test("Opening the drawer doesn't make its window key, so the app's text field keeps the keyboard")
        func openingLeavesTheKeyWindow() throws {
            let suite = "DrawerWindowTests.\(#function).\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let drawer = DebugDrawer(defaults: defaults)
            let presentation = DrawerPresentation()
            let sut = DrawerSceneWindow(scene: nil, drawer: drawer, presentation: presentation)

            presentation.isOpen = true
            defer { presentation.isOpen = false }

            #expect(!sut.isKeyWindow)
        }

        @Test("The drawer's window is the drawer's own, which plugins that draw the app's windows leave out")
        func drawerWindowIsLeftOut() throws {
            let suite = "DrawerWindowTests.\(#function).\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let drawer = DebugDrawer(defaults: defaults)
            let presentation = DrawerPresentation()
            let sut = DrawerSceneWindow(scene: nil, drawer: drawer, presentation: presentation)
            let appWindow = UIWindow(frame: .zero)

            #expect(isDebugDrawerWindow(sut))
            #expect(!isDebugDrawerWindow(appWindow))
        }
    }
#endif
