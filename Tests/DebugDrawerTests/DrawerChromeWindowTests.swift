// The drawer's windows are AppKit's and UIKit's.
#if os(macOS)
    import AppKit
    @testable import DebugDrawer
    import DebugDrawerTestSupport
    import SwiftUI
    import Testing

    private struct ChromeReadoutPlugin: DebugDrawerPlugin {
        var id = "ChromeReadoutPlugin"
        var title = "Readout"
        var icon = "gauge"
        var body: some View { EmptyView() }
        var hud: Text? { Text("42 FPS") }
    }

    // Each test that needs a drawer makes one of its own over a UserDefaults suite named for the
    // test, removed when the test ends.
    @MainActor
    @Suite("Drawer HUD and toast windows")
    struct DrawerChromeWindowTests {
        @Test("An AppKit window attached with attach(to:) shows the HUD at its corner and the toast top trailing, each in a panel just its size")
        func attachedWindowShowsHUDAndToast() throws {
            let suite = temporarySuiteName("DrawerChromeWindowTests.\(#function)")
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let drawer = DebugDrawer(defaults: defaults)
            drawer.registerGlobal(ChromeReadoutPlugin())
            drawer.hudLayout.pinned = ["ChromeReadoutPlugin"]
            drawer.postToast("Saved the order", fromPlugin: "ChromeReadoutPlugin")
            // Borderless and far off screen: ordered in, so the panels can be, but never seen.
            let window = NSWindow(
                contentRect: CGRect(x: -30000, y: -30000, width: 900, height: 600),
                styleMask: .borderless, backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            window.contentView = NSTextField(labelWithString: "AppKit")
            window.orderFront(nil)
            defer { window.close() }

            drawer.attach(to: window)
            let attachment = try #require(drawer.attachments.first { $0.window === window })
            for panel in [attachment.hud, attachment.toast] {
                panel.contentView?.subviews.first?.layoutSubtreeIfNeeded()
            }

            let hud = attachment.hud
            let toast = attachment.toast
            #expect(hud.parent === window)
            #expect(toast.parent === window)
            #expect(hud.isVisible && hud.alphaValue == 1 && !hud.ignoresMouseEvents)
            #expect(toast.isVisible && toast.alphaValue == 1 && !toast.ignoresMouseEvents)
            #expect(hud.contentSize.width > 0 && hud.contentSize.height > 0)
            #expect(toast.contentSize.width > 0 && toast.contentSize.height > 0)
            #expect(hud.frame == CGRect(
                x: -30000 + 12, y: -30000 + 600 - 12 - hud.contentSize.height,
                width: hud.contentSize.width, height: hud.contentSize.height
            ))
            #expect(toast.frame == CGRect(
                x: -30000 + 900 - 12 - toast.contentSize.width, y: -30000 + 600 - 12 - toast.contentSize.height,
                width: toast.contentSize.width, height: toast.contentSize.height
            ))
        }

        @Test("A click beside the HUD and the toast lands in the app's window: neither panel covers it")
        func clickBesideChromeReachesApp() throws {
            let suite = temporarySuiteName("DrawerChromeWindowTests.\(#function)")
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let drawer = DebugDrawer(defaults: defaults)
            drawer.registerGlobal(ChromeReadoutPlugin())
            drawer.hudLayout.pinned = ["ChromeReadoutPlugin"]
            drawer.postToast("Saved the order", fromPlugin: "ChromeReadoutPlugin")
            let window = NSWindow(
                contentRect: CGRect(x: -30000, y: -30000, width: 900, height: 600),
                styleMask: .borderless, backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: Color.red.frame(width: 900, height: 600))
            window.orderFront(nil)
            defer { window.close() }
            drawer.attach(to: window)
            let attachment = try #require(drawer.attachments.first { $0.window === window })
            for panel in [attachment.hud, attachment.toast] {
                panel.contentView?.subviews.first?.layoutSubtreeIfNeeded()
            }
            // Just right of the HUD's card and just left of the toast, at their height.
            let besideHUD = CGPoint(x: attachment.hud.frame.maxX + 2, y: attachment.hud.frame.midY)
            let besideToast = CGPoint(x: attachment.toast.frame.minX - 2, y: attachment.toast.frame.midY)
            let drawerWindows = (window.childWindows ?? []).filter(isDebugDrawerWindow)

            let hits = [besideHUD, besideToast].map { window.contentView?.hitTest(window.convertPoint(fromScreen: $0)) }

            #expect(!drawerWindows.isEmpty)
            #expect(drawerWindows.allSatisfy { !$0.frame.contains(besideHUD) && !$0.frame.contains(besideToast) })
            #expect(hits.allSatisfy { $0 != nil && $0?.window === window })
        }

        @Test("With nothing pinned and no toast, the HUD and toast panels are clear and ignore the mouse")
        func emptyPanelsLetClicksThrough() throws {
            let suite = temporarySuiteName("DrawerChromeWindowTests.\(#function)")
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let drawer = DebugDrawer(defaults: defaults)
            let window = NSWindow(
                contentRect: CGRect(x: -30000, y: -30000, width: 900, height: 600),
                styleMask: .borderless, backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            window.orderFront(nil)
            defer { window.close() }
            let panels = [
                DrawerChromePanel(role: .hud, host: window, drawer: drawer),
                DrawerChromePanel(role: .toast, host: window, drawer: drawer)
            ]

            for panel in panels {
                panel.contentView?.subviews.first?.layoutSubtreeIfNeeded()
            }

            #expect(panels.allSatisfy { $0.contentSize == .zero && $0.alphaValue == 0 && $0.ignoresMouseEvents })
        }

        @Test("Dragging the HUD moves its panel with the mouse, kept inside the window, and saves where it was dropped")
        func draggingMovesThePanel() throws {
            let suite = temporarySuiteName("DrawerChromeWindowTests.\(#function)")
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let drawer = DebugDrawer(defaults: defaults)
            drawer.registerGlobal(ChromeReadoutPlugin())
            drawer.hudLayout.pinned = ["ChromeReadoutPlugin"]
            let window = NSWindow(
                contentRect: CGRect(x: -30000, y: -30000, width: 900, height: 600),
                styleMask: .borderless, backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            window.orderFront(nil)
            defer { window.close() }
            let sut = DrawerChromePanel(role: .hud, host: window, drawer: drawer)
            sut.contentView?.subviews.first?.layoutSubtreeIfNeeded()
            let start = sut.frame
            // The gesture began 10 points right and 10 down of the press; the mouse is now 100
            // right and 50 down of it, and then far past the window's leading edge.
            let press = CGPoint(x: start.midX, y: start.midY)

            sut.drag(translation: CGSize(width: 10, height: 10), mouse: CGPoint(x: press.x + 10, y: press.y - 10))
            sut.drag(translation: CGSize(width: 100, height: 50), mouse: CGPoint(x: press.x + 100, y: press.y - 50))
            let moved = sut.frame
            sut.drag(translation: CGSize(width: -5000, height: 50), mouse: CGPoint(x: press.x - 5000, y: press.y - 50))
            let kept = sut.frame
            sut.endDrag()

            #expect(start.size.width > 0)
            #expect(moved == start.offsetBy(dx: 100, dy: -50))
            #expect(kept.minX == -30000)
            #expect(drawer.hudLayout.origin == CGPoint(x: 0, y: 12 + 50))
        }

        @Test("The HUD's frame keeps the card inside the window's content, and its corner round-trips",
              arguments: [
                  (CGPoint?.none, CGRect(x: 112, y: 588 - 40, width: 80, height: 40)),
                  (CGPoint(x: 300, y: 200), CGRect(x: 400, y: 400 - 40, width: 80, height: 40)),
                  (CGPoint(x: 5000, y: 5000), CGRect(x: 100 + 900 - 80, y: 0, width: 80, height: 40)),
                  (CGPoint(x: -50, y: -50), CGRect(x: 100, y: 600 - 40, width: 80, height: 40))
              ])
        func hudFrame(origin: CGPoint?, expected: CGRect) {
            let content = CGRect(x: 100, y: 0, width: 900, height: 600)
            let size = CGSize(width: 80, height: 40)

            let actual = DrawerChromePanel.hudFrame(origin: origin, size: size, in: content)
            let corner = DrawerChromePanel.hudOrigin(of: actual, in: content)

            #expect(actual == expected)
            #expect(DrawerChromePanel.hudFrame(origin: corner, size: size, in: content) == actual)
        }

        @Test("The toast sits at the content's top trailing corner, inset by its margin")
        func toastFrame() {
            let content = CGRect(x: 100, y: 0, width: 900, height: 600)
            let expected = CGRect(x: 1000 - 12 - 300, y: 600 - 12 - 60, width: 300, height: 60)

            let actual = DrawerChromePanel.toastFrame(size: CGSize(width: 300, height: 60), in: content)

            #expect(actual == expected)
        }

        @Test("A readout in an attached window's HUD panel makes its plugin visible, once per window")
        func hudPanelReportsVisibility() throws {
            let suite = temporarySuiteName("DrawerChromeWindowTests.\(#function)")
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let drawer = DebugDrawer(defaults: defaults)
            drawer.registerGlobal(ChromeReadoutPlugin())
            drawer.hudLayout.pinned = ["ChromeReadoutPlugin"]
            let window = NSWindow(
                contentRect: CGRect(x: -30000, y: -30000, width: 900, height: 600),
                styleMask: .borderless, backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            window.contentView = NSTextField(labelWithString: "AppKit")
            window.orderFront(nil)
            defer { window.close() }

            drawer.attach(to: window)
            let attachment = try #require(drawer.attachments.first { $0.window === window })
            attachment.hud.contentView?.subviews.first?.layoutSubtreeIfNeeded()

            #expect(drawer.visibleContentCounts["ChromeReadoutPlugin", default: 0] == 1)
        }
    }

    // debugDrawer() shows the shared drawer, so these tests stay on it, in the serialized suite of
    // the shared drawer's tests.
    extension SharedDrawerTests {
        @MainActor
        @Suite("Drawer HUD and toast windows under debugDrawer()")
        struct SharedDrawerChromeWindowTests {
            @Test("A debugDrawer() window and an AppKit window attached with attach(to:) show the same HUD and toast")
            func bothEntryPointsShowTheSameChrome() throws {
                let drawer = DebugDrawer.shared
                let previous = drawer.hudLayout
                drawer.registerGlobal(ChromeReadoutPlugin())
                drawer.hudLayout = HUDLayout()
                drawer.hudLayout.pinned = ["ChromeReadoutPlugin"]
                drawer.postToast("Saved the order", fromPlugin: "ChromeReadoutPlugin")
                defer {
                    drawer.dismissToast()
                    drawer.hudLayout = previous
                    drawer.unregisterGlobal(id: "ChromeReadoutPlugin")
                }
                let swiftUIWindow = NSWindow(
                    contentRect: CGRect(x: -30000, y: -30000, width: 900, height: 600),
                    styleMask: .borderless, backing: .buffered, defer: false
                )
                let appKitWindow = NSWindow(
                    contentRect: CGRect(x: -31000, y: -30000, width: 900, height: 600),
                    styleMask: .borderless, backing: .buffered, defer: false
                )
                let host = NSHostingView(rootView: Text("SwiftUI").frame(width: 900, height: 600).debugDrawer())
                swiftUIWindow.contentView = host
                appKitWindow.contentView = NSTextField(labelWithString: "AppKit")
                for window in [swiftUIWindow, appKitWindow] {
                    window.isReleasedWhenClosed = false
                    window.orderFront(nil)
                }
                defer { [swiftUIWindow, appKitWindow].forEach { $0.close() } }
                host.layoutSubtreeIfNeeded()

                drawer.attach(to: appKitWindow)
                let swiftUIDrawer = try #require(drawer.attachments.first { $0.window === swiftUIWindow })
                let appKitDrawer = try #require(drawer.attachments.first { $0.window === appKitWindow })
                let panels = [swiftUIDrawer.hud, swiftUIDrawer.toast, appKitDrawer.hud, appKitDrawer.toast]
                for panel in panels {
                    panel.contentView?.subviews.first?.layoutSubtreeIfNeeded()
                }

                #expect(panels.allSatisfy { $0.isVisible && $0.alphaValue == 1 })
                #expect(swiftUIDrawer.hud.frame.size == appKitDrawer.hud.frame.size)
                #expect(swiftUIDrawer.toast.frame.size == appKitDrawer.toast.frame.size)
                #expect(swiftUIDrawer.hud.frame.offsetBy(dx: -1000, dy: 0) == appKitDrawer.hud.frame)
                #expect(swiftUIDrawer.toast.frame.offsetBy(dx: -1000, dy: 0) == appKitDrawer.toast.frame)
            }

            @Test("A window with both debugDrawer() and attach(to:) has one HUD and one toast")
            func bothInOneWindowDrawOnce() throws {
                let drawer = DebugDrawer.shared
                let previous = drawer.hudLayout
                drawer.registerGlobal(ChromeReadoutPlugin())
                drawer.hudLayout = HUDLayout()
                drawer.hudLayout.pinned = ["ChromeReadoutPlugin"]
                drawer.postToast("Saved the order", fromPlugin: "ChromeReadoutPlugin")
                defer {
                    drawer.dismissToast()
                    drawer.hudLayout = previous
                    drawer.unregisterGlobal(id: "ChromeReadoutPlugin")
                }
                let window = NSWindow(
                    contentRect: CGRect(x: -30000, y: -30000, width: 900, height: 600),
                    styleMask: .borderless, backing: .buffered, defer: false
                )
                window.isReleasedWhenClosed = false
                let host = NSHostingView(rootView: Text("SwiftUI").frame(width: 900, height: 600).debugDrawer())
                window.contentView = host
                window.orderFront(nil)
                defer { window.close() }
                host.layoutSubtreeIfNeeded()

                drawer.attach(to: window)

                let attachments = drawer.attachments.filter { $0.window === window }
                let chrome = (window.childWindows ?? []).compactMap { $0 as? DrawerChromePanel }
                #expect(attachments.count == 1)
                #expect(chrome.filter { $0.role == .hud }.count == 1)
                #expect(chrome.filter { $0.role == .toast }.count == 1)
            }
        }
    }
#elseif os(iOS)
    @testable import DebugDrawer
    import DebugDrawerTestSupport
    import SwiftUI
    import Testing
    import UIKit

    private struct ChromeReadoutPlugin: DebugDrawerPlugin {
        var id = "ChromeReadoutPlugin"
        var title = "Readout"
        var icon = "gauge"
        var body: some View { EmptyView() }
        var hud: Text? { Text("42 FPS") }
    }

    @MainActor
    @Suite("Drawer HUD and toast window")
    struct DrawerChromeWindowTests {
        // UIKit can't make a window in xctest, which runs package tests on Mac Catalyst without an
        // NSApplication.
        #if !targetEnvironment(macCatalyst)
            @Test("The HUD window draws the HUD and the toast and takes a touch only on them; one beside them reaches the app's windows")
            func touchesOnlyOnHUDAndToast() throws {
                let suite = temporarySuiteName("DrawerChromeWindowTests.\(#function)")
                let defaults = try #require(UserDefaults(suiteName: suite))
                defer { defaults.removePersistentDomain(forName: suite) }
                let drawer = DebugDrawer(defaults: defaults)
                drawer.registerGlobal(ChromeReadoutPlugin())
                drawer.hudLayout.pinned = ["ChromeReadoutPlugin"]
                drawer.postToast("Saved the order", fromPlugin: "ChromeReadoutPlugin")
                let sut = DrawerChromeWindow(scene: nil, drawer: drawer)
                sut.frame = CGRect(x: 0, y: 0, width: 1024, height: 768)
                defer { sut.isHidden = true }
                sut.layoutIfNeeded()
                let hud = try #require(sut.frames.hud)
                let toast = try #require(sut.frames.toast)
                let middle = CGPoint(x: 512, y: 500)
                let besideHUD = CGPoint(x: hud.maxX + 2, y: hud.midY)

                let onHUD = sut.hitTest(CGPoint(x: hud.midX, y: hud.midY), with: nil)
                let onToast = sut.hitTest(CGPoint(x: toast.midX, y: toast.midY), with: nil)
                let inMiddle = sut.hitTest(middle, with: nil)
                let nextToHUD = sut.hitTest(besideHUD, with: nil)

                #expect(sut.windowLevel > DrawerOverlayWindow.level)
                #expect(sut.windowLevel < DrawerSceneWindow.level)
                #expect(hud.origin == CGPoint(x: 12, y: 12))
                // Within half a point: layout leaves the toast's edge a hair off the whole point.
                #expect((toast.maxX - (1024 - 12)).magnitude < 0.5)
                #expect(onHUD != nil)
                #expect(onToast != nil)
                #expect(inMiddle == nil)
                #expect(nextToHUD == nil)
            }

            // UIKit shows a readout's context menu in views it adds to the HUD window beside the
            // hosted content, and closes it on a tap the window gets; a plain view added the same
            // way stands in for them, as opening a real menu takes a touch.
            @Test("While an added view, such as an open context menu's, is in the HUD window it takes every touch; once it's gone, the app gets them")
            func addedViewTakesEveryTouch() throws {
                let suite = temporarySuiteName("DrawerChromeWindowTests.\(#function)")
                let defaults = try #require(UserDefaults(suiteName: suite))
                defer { defaults.removePersistentDomain(forName: suite) }
                let drawer = DebugDrawer(defaults: defaults)
                drawer.registerGlobal(ChromeReadoutPlugin())
                drawer.hudLayout.pinned = ["ChromeReadoutPlugin"]
                let sut = DrawerChromeWindow(scene: nil, drawer: drawer)
                sut.frame = CGRect(x: 0, y: 0, width: 1024, height: 768)
                defer { sut.isHidden = true }
                sut.layoutIfNeeded()
                let hud = try #require(sut.frames.hud)
                let menu = UIView(frame: CGRect(x: hud.minX, y: hud.maxY + 8, width: 224, height: 40))
                let onMenuPoint = CGPoint(x: menu.frame.midX, y: menu.frame.midY)
                let middle = CGPoint(x: 512, y: 500)
                sut.addSubview(menu)

                let onMenu = sut.hitTest(onMenuPoint, with: nil)
                let inMiddleWithMenu = sut.hitTest(middle, with: nil)
                menu.removeFromSuperview()
                let afterMenu = [onMenuPoint, middle].map { sut.hitTest($0, with: nil) }

                #expect(onMenu === menu)
                #expect(inMiddleWithMenu != nil)
                #expect(afterMenu.allSatisfy { $0 == nil })
            }

            @Test("With nothing pinned and no toast, the drawer's HUD window takes no touch")
            func emptyWindowTakesNoTouch() throws {
                let suite = temporarySuiteName("DrawerChromeWindowTests.\(#function)")
                let defaults = try #require(UserDefaults(suiteName: suite))
                defer { defaults.removePersistentDomain(forName: suite) }
                let sut = DrawerChromeWindow(scene: nil, drawer: DebugDrawer(defaults: defaults))
                sut.frame = CGRect(x: 0, y: 0, width: 1024, height: 768)
                defer { sut.isHidden = true }
                sut.layoutIfNeeded()
                let corners = [CGPoint(x: 20, y: 20), CGPoint(x: 1000, y: 20), CGPoint(x: 512, y: 384)]

                let actual = corners.map { sut.hitTest($0, with: nil) }

                #expect(sut.frames.hud == nil)
                #expect(sut.frames.toast == nil)
                #expect(actual.allSatisfy { $0 == nil })
            }
        #endif

        @Test("The touch rule: a point on the HUD's card or the toast belongs to the drawer, any other the app's",
              arguments: [
                  (CGPoint(x: 20, y: 20), true),
                  (CGPoint(x: 900, y: 30), true),
                  (CGPoint(x: 500, y: 400), false),
                  (CGPoint(x: 120, y: 20), false)
              ])
        func touchRule(point: CGPoint, expected: Bool) {
            let sut = DrawerChromeFrames()
            sut.hud = CGRect(x: 12, y: 12, width: 100, height: 40)
            sut.toast = CGRect(x: 700, y: 12, width: 312, height: 60)

            let actual = sut.contains(point)

            #expect(actual == expected)
        }
    }
#endif
