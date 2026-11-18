// The drawer's windows are AppKit's and UIKit's.
#if os(macOS)
    import AppKit
    @testable import DebugDrawer
    import SwiftUI
    import Testing

    // Serialized: these tests attach windows to the one shared drawer.
    @MainActor
    @Suite("Drawer hit testing", .serialized)
    struct DrawerHitTestingTests {
        @Test("While the drawer is open, a click beside the panel lands in the app's window, outside the panel's")
        func clickBesidePanelReachesApp() throws {
            // Borderless and far off screen: ordered in, so the panel can be, but never seen.
            let window = NSWindow(
                contentRect: CGRect(x: -30000, y: -30000, width: 900, height: 600),
                styleMask: .borderless, backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: Color.red.frame(width: 900, height: 600))
            window.orderFront(nil)
            defer { window.close() }
            DebugDrawer.shared.attach(to: window)
            let attachment = try #require(DebugDrawer.shared.attachments.first { $0.window === window })
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
            let window = NSWindow(
                contentRect: CGRect(x: -30000, y: -30000, width: 900, height: 600),
                styleMask: .borderless, backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: Color.red.frame(width: 900, height: 600))
            window.orderFront(nil)
            defer { window.close() }
            DebugDrawer.shared.attach(to: window)
            let attachment = try #require(DebugDrawer.shared.attachments.first { $0.window === window })

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
        @Test("While the drawer is open, its window takes a touch on the panel and lets one beside it fall through to the app's windows")
        func touchBesidePanelFallsThrough() {
            let presentation = DrawerPresentation()
            presentation.isOpen = true
            presentation.panelFrame = CGRect(x: 700, y: 20, width: 316, height: 728)
            let sut = DrawerSceneWindow(scene: nil, drawer: .shared, presentation: presentation)
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

        @Test("While the drawer is closed, its window takes no touch, even where the panel was")
        func touchWhileClosedFallsThrough() {
            let presentation = DrawerPresentation()
            presentation.panelFrame = CGRect(x: 700, y: 20, width: 316, height: 728)
            let sut = DrawerSceneWindow(scene: nil, drawer: .shared, presentation: presentation)
            sut.frame = CGRect(x: 0, y: 0, width: 1024, height: 768)
            let wherePanelWas = CGPoint(x: 800, y: 384)

            let actual = sut.hitTest(wherePanelWas, with: nil)

            #expect(actual == nil)
        }

        @Test("While a compact drawer is open, its window takes a touch outside the panel, where its backdrop closes the drawer")
        func touchOutsideCompactPanelIsTaken() {
            let presentation = DrawerPresentation()
            presentation.isOpen = true
            presentation.layout = .compact
            presentation.panelFrame = CGRect(x: 8, y: 70, width: 386, height: 760)
            let sut = DrawerSceneWindow(scene: nil, drawer: .shared, presentation: presentation)
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
