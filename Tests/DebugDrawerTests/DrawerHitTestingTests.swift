// The views are hosted on the Mac.
#if os(macOS)
    import AppKit
    @testable import DebugDrawer
    import SwiftUI
    import Testing
    import ViewInspector

    // Serialized: these tests open and close the one shared drawer.
    @MainActor
    @Suite("Drawer hit testing", .serialized)
    struct DrawerHitTestingTests {
        @Test("While the drawer is open, a click beside the panel reaches the app, not the drawer's tag view")
        func clickBesidePanelReachesApp() {
            DebugDrawer.shared.isOpen = true
            defer { DebugDrawer.shared.isOpen = false }
            let host = NSHostingView(rootView: Color.red.frame(width: 800, height: 600).debugDrawer())
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = host
            host.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
            host.layoutSubtreeIfNeeded()
            // The panel is 340 points wide along the trailing edge, so x = 100 is the app's.
            let besidePanel = CGPoint(x: 100, y: 300)

            let actual = host.hitTest(besidePanel)

            #expect(actual != nil)
            #expect(actual?.accessibilityIdentifier() != debugDrawerOverlayIdentifier)
        }

        @Test("SwiftUI routes no touch or click to the drawer's tag view, so one beside the open panel reaches the app's controls")
        func tagViewTakesNoSwiftUIHits() throws {
            DebugDrawer.shared.isOpen = true
            defer { DebugDrawer.shared.isOpen = false }
            let sut = Color.red.debugDrawer()

            let actual = try sut.inspect().find(DebugDrawerTagView.self).allowsHitTesting()

            #expect(!actual)
        }

        @Test("While the drawer is closed, a click anywhere reaches the app, not the drawer's tag view")
        func clickWhileClosedReachesApp() {
            DebugDrawer.shared.isOpen = false
            let host = NSHostingView(rootView: Color.red.frame(width: 800, height: 600).debugDrawer())
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = host
            host.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
            host.layoutSubtreeIfNeeded()
            let underPanel = CGPoint(x: 700, y: 300)

            let actual = host.hitTest(underPanel)

            #expect(actual != nil)
            #expect(actual?.accessibilityIdentifier() != debugDrawerOverlayIdentifier)
        }

        @Test("The drawer's tag view takes no click, even at a point inside it")
        func tagViewRefusesClicks() {
            let sut = DebugDrawerTagNSView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
            let inside = CGPoint(x: 50, y: 50)

            let actual = sut.hitTest(inside)

            #expect(actual == nil)
        }
    }
#elseif os(iOS)
    @testable import DebugDrawer
    import SwiftUI
    import Testing
    import UIKit

    // Serialized: these tests open and close the one shared drawer.
    @MainActor
    @Suite("Drawer hit testing", .serialized)
    struct DrawerHitTestingTests {
        @Test("While the drawer is open, the tag view carries the overlay identifier and takes no touch, and a hit beside the panel misses it")
        func touchBesidePanelReachesApp() throws {
            DebugDrawer.shared.isOpen = true
            defer { DebugDrawer.shared.isOpen = false }
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1024, height: 768))
            window.rootViewController = UIHostingController(rootView: Color.red.debugDrawer())
            window.isHidden = false
            defer { window.isHidden = true }
            window.layoutIfNeeded()
            // The panel is 340 points wide along the trailing edge, so x = 100 is the app's.
            let besidePanel = CGPoint(x: 100, y: 384)
            func tagged(_ view: UIView) -> UIView? {
                if view.tag == debugDrawerViewTag { return view }
                return view.subviews.lazy.compactMap(tagged).first
            }
            let tag = try #require(tagged(window))
            let hostView = try #require(window.rootViewController?.view)
            // The tag view and the views SwiftUI wraps it in, up to the app's hosting view.
            let tagAndWrappers = Array(sequence(first: tag, next: \.superview).prefix { $0 !== hostView })

            let actual = window.hitTest(besidePanel, with: nil)

            #expect(tag.accessibilityIdentifier == debugDrawerOverlayIdentifier)
            #expect(!tag.isUserInteractionEnabled)
            #expect(actual != nil)
            #expect(!tagAndWrappers.contains { $0 === actual })
        }
    }
#endif
