// The drawer's windows are AppKit's and UIKit's.
#if os(macOS)
    import AppKit
    @testable import DebugDrawer
    import DebugDrawerTestSupport
    import SwiftUI
    import Testing

    // Each test makes a drawer of its own over a UserDefaults suite named for the test, removed
    // when the test ends.
    @MainActor
    @Suite("Drawer hit testing")
    struct DrawerHitTestingTests {
        @Test("While the drawer is open, a click beside the panel lands in the app's window, outside the panel's")
        func clickBesidePanelReachesApp() throws {
            let suite = temporarySuiteName("DrawerHitTestingTests.\(#function)")
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let drawer = DebugDrawer(defaults: defaults)
            // Borderless and far off screen: ordered in, so the panel can be, but never seen.
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
            attachment.presentation.isOpen = true
            // 100 points from the window's leading edge; the panel is 316 points at the trailing edge.
            let besidePanel = CGPoint(x: window.frame.minX + 100, y: window.frame.midY)

            // The content view's superview is the window's frame view, in window coordinates.
            let actual = window.contentView?.hitTest(window.convertPoint(fromScreen: besidePanel))

            #expect(attachment.panel.isVisible)
            #expect(!attachment.panel.frame.contains(besidePanel))
            #expect(actual != nil)
            #expect(actual?.window === window)
        }

        @Test("While the drawer is closed, its panel is off screen, so a click anywhere reaches the app")
        func clickWhileClosedReachesApp() throws {
            let suite = temporarySuiteName("DrawerHitTestingTests.\(#function)")
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let drawer = DebugDrawer(defaults: defaults)
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

            let actual = attachment.panel.isVisible

            #expect(!attachment.presentation.isOpen)
            #expect(!actual)
            #expect(window.childWindows?.contains(attachment.panel) != true)
        }
    }
#elseif os(iOS)
    @testable import DebugDrawer
    import SwiftUI
    import Testing
    import UIKit

    @MainActor
    @Suite("Drawer hit testing")
    struct DrawerHitTestingTests {
        // UIKit can't make a window in xctest, which runs package tests on Mac Catalyst without an
        // NSApplication.
        #if !targetEnvironment(macCatalyst)
            @Test("While the drawer is open, its window takes a touch on the panel and lets one beside it fall through to the app's windows")
            func touchBesidePanelFallsThrough() throws {
                let suite = temporarySuiteName("DrawerHitTestingTests.\(#function)")
                let defaults = try #require(UserDefaults(suiteName: suite))
                defer { defaults.removePersistentDomain(forName: suite) }
                let drawer = DebugDrawer(defaults: defaults)
                let presentation = DrawerPresentation()
                presentation.isOpen = true
                presentation.panelFrame = CGRect(x: 700, y: 20, width: 316, height: 728)
                let sut = DrawerSceneWindow(scene: nil, drawer: drawer, presentation: presentation)
                sut.frame = CGRect(x: 0, y: 0, width: 1024, height: 768)
                sut.isHidden = false
                defer { sut.isHidden = true }
                sut.layoutIfNeeded()
                let besidePanel = CGPoint(x: 100, y: 384)
                let onPanel = CGPoint(x: 800, y: 384)

                let beside = sut.hitTest(besidePanel, with: nil)
                let on = sut.hitTest(onPanel, with: nil)

                #expect(beside == nil)
                #expect(on != nil)
            }

            // UIKit shows a context menu from the panel (a section header's) in views it adds to the
            // drawer's window beside its root view, and closes it on a tap the window gets; a plain
            // view added the same way stands in for them, as opening a real menu takes a touch.
            @Test("An added view, such as a context menu's, makes the drawer's window take touches beside the panel; once it's gone, the app does")
            func addedViewTakesTouchesOutsidePanel() throws {
                let suite = temporarySuiteName("DrawerHitTestingTests.\(#function)")
                let defaults = try #require(UserDefaults(suiteName: suite))
                defer { defaults.removePersistentDomain(forName: suite) }
                let drawer = DebugDrawer(defaults: defaults)
                let presentation = DrawerPresentation()
                presentation.isOpen = true
                let panelFrame = CGRect(x: 700, y: 20, width: 316, height: 728)
                presentation.panelFrame = panelFrame
                let sut = DrawerSceneWindow(scene: nil, drawer: drawer, presentation: presentation)
                sut.frame = CGRect(x: 0, y: 0, width: 1024, height: 768)
                sut.isHidden = false
                defer { sut.isHidden = true }
                sut.layoutIfNeeded()
                // A menu item past the panel's leading edge, and a point beside the panel well away from it.
                let menu = UIView(frame: CGRect(x: 600, y: 80, width: 224, height: 40))
                let onMenuPoint = CGPoint(x: 620, y: 100)
                let besidePanel = CGPoint(x: 100, y: 384)
                let beforeMenu = sut.hitTest(besidePanel, with: nil)
                sut.addSubview(menu)

                let onMenu = sut.hitTest(onMenuPoint, with: nil)
                let besidePanelWithMenu = sut.hitTest(besidePanel, with: nil)
                menu.removeFromSuperview()
                let afterMenu = [onMenuPoint, besidePanel].map { sut.hitTest($0, with: nil) }

                #expect(!panelFrame.contains(onMenuPoint))
                #expect(beforeMenu == nil)
                #expect(onMenu === menu)
                #expect(besidePanelWithMenu != nil)
                #expect(afterMenu.allSatisfy { $0 == nil })
            }

            @Test("While the drawer is closed, its window takes no touch, even where the panel was")
            func touchWhileClosedFallsThrough() throws {
                let suite = temporarySuiteName("DrawerHitTestingTests.\(#function)")
                let defaults = try #require(UserDefaults(suiteName: suite))
                defer { defaults.removePersistentDomain(forName: suite) }
                let drawer = DebugDrawer(defaults: defaults)
                let presentation = DrawerPresentation()
                presentation.panelFrame = CGRect(x: 700, y: 20, width: 316, height: 728)
                let sut = DrawerSceneWindow(scene: nil, drawer: drawer, presentation: presentation)
                sut.frame = CGRect(x: 0, y: 0, width: 1024, height: 768)
                let wherePanelWas = CGPoint(x: 800, y: 384)

                let actual = sut.hitTest(wherePanelWas, with: nil)

                #expect(actual == nil)
            }

            @Test("While a compact drawer is open, its window takes a touch outside the panel, where its backdrop closes the drawer")
            func touchOutsideCompactPanelIsTaken() throws {
                let suite = temporarySuiteName("DrawerHitTestingTests.\(#function)")
                let defaults = try #require(UserDefaults(suiteName: suite))
                defer { defaults.removePersistentDomain(forName: suite) }
                let drawer = DebugDrawer(defaults: defaults)
                let presentation = DrawerPresentation()
                presentation.isOpen = true
                presentation.layout = .compact
                presentation.panelFrame = CGRect(x: 8, y: 70, width: 386, height: 760)
                let sut = DrawerSceneWindow(scene: nil, drawer: drawer, presentation: presentation)
                sut.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
                sut.isHidden = false
                defer { sut.isHidden = true }
                sut.layoutIfNeeded()
                let statusBar = CGPoint(x: 201, y: 20)
                let onPanel = CGPoint(x: 201, y: 437)

                let outside = sut.hitTest(statusBar, with: nil)
                let on = sut.hitTest(onPanel, with: nil)

                #expect(outside != nil)
                #expect(on != nil)
            }
        #endif

        @Test("The touch rule: only an open drawer takes a touch; a regular one only on its panel, a compact one anywhere",
              arguments: [
                  (CGPoint(x: 800, y: 384), DrawerPanelLayout.regular, true, true),
                  (CGPoint(x: 699, y: 384), DrawerPanelLayout.regular, true, false),
                  (CGPoint(x: 800, y: 384), DrawerPanelLayout.regular, false, false),
                  (CGPoint(x: 800, y: 384), DrawerPanelLayout.compact, true, true),
                  (CGPoint(x: 699, y: 10), DrawerPanelLayout.compact, true, true),
                  (CGPoint(x: 699, y: 10), DrawerPanelLayout.compact, false, false)
              ])
        func touchRule(point: CGPoint, layout: DrawerPanelLayout, isOpen: Bool, expected: Bool) {
            let panelFrame = CGRect(x: 700, y: 20, width: 316, height: 728)

            let actual = DrawerSceneWindow.takesTouch(at: point, panelFrame: panelFrame, layout: layout, isOpen: isOpen)

            #expect(actual == expected)
        }

        @Test("With no panel drawn, the drawer's window takes no touch, at either width",
              arguments: [DrawerPanelLayout.regular, .compact])
        func noPanelTakesNoTouch(layout: DrawerPanelLayout) {
            let actual = DrawerSceneWindow.takesTouch(at: CGPoint(x: 10, y: 10), panelFrame: nil, layout: layout, isOpen: true)

            #expect(!actual)
        }
    }
#endif
