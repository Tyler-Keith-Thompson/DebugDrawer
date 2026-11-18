// The views are hosted on the Mac.
#if os(macOS)
    import AppKit
    @testable import DebugDrawer
    import SwiftUI
    import Testing

    // Serialized: these tests open and close the one shared drawer.
    @MainActor
    @Suite("Drawer hit testing", .serialized)
    struct DrawerHitTestingTests {
        @Test("While the drawer is open, a click beside the panel reaches the app, not the drawer")
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

        @Test("While the drawer is closed, a click anywhere reaches the app, not the drawer")
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
        @Test("While the drawer is open, a touch beside the panel reaches the app, not the drawer")
        func touchBesidePanelReachesApp() {
            DebugDrawer.shared.isOpen = true
            defer { DebugDrawer.shared.isOpen = false }
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1024, height: 768))
            window.rootViewController = UIHostingController(rootView: Color.red.debugDrawer())
            window.isHidden = false
            defer { window.isHidden = true }
            window.layoutIfNeeded()
            // The panel is 340 points wide along the trailing edge, so x = 100 is the app's.
            let besidePanel = CGPoint(x: 100, y: 384)

            let actual = window.hitTest(besidePanel, with: nil)

            #expect(actual != nil)
            #expect(actual?.accessibilityIdentifier != debugDrawerOverlayIdentifier)
        }
    }
#endif
