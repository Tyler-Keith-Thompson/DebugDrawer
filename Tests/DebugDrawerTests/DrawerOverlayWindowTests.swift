#if os(macOS) && DEBUG
    import AppKit
    @testable import DebugDrawer
    import SwiftUI
    import Testing

    // The host windows are never shown, so the overlay stays out of the window list.
    @MainActor
    @Suite("Drawer overlay window")
    struct DrawerOverlayWindowTests {
        @Test("The overlay window ignores the mouse, never becomes key or main, and is the drawer's own")
        func overlayTakesNoEvents() {
            let host = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: true)

            let sut = DrawerOverlayWindow(over: host, content: Color.clear)

            #expect(sut.ignoresMouseEvents)
            #expect(!sut.canBecomeKey)
            #expect(!sut.canBecomeMain)
            #expect(isDebugDrawerWindow(sut))
            #expect(!isDebugDrawerWindow(host))
        }

        @Test("The overlay window covers its window's content view and follows it when the window resizes")
        func overlayFollowsTheContentView() throws {
            let host = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: true)
            let sut = DrawerOverlayWindow(over: host, content: Color.clear)
            let initial = sut.frame
            let expectedInitial = CGRect(x: 100, y: 100, width: 400, height: 300)

            host.setContentSize(CGSize(width: 500, height: 200))
            sut.followHost()
            let content = try #require(host.contentView)
            let expected = host.convertToScreen(content.convert(content.bounds, to: nil))

            #expect(initial == expectedInitial)
            #expect(sut.frame == expected)
            #expect(sut.parent == nil)
        }

        @Test("A rectangle in the window's base coordinates comes out in the overlay's, from its top-leading corner")
        func convertsFromTheHost() {
            let host = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: true)
            let sut = DrawerOverlayWindow(over: host, content: Color.clear)
            // 20 pt from the left and 30 from the bottom of a 300 pt content view, 50 tall: 220
            // from its top.
            let expected = CGRect(x: 20, y: 220, width: 100, height: 50)

            let actual = sut.convert(fromHost: CGRect(x: 20, y: 30, width: 100, height: 50))

            #expect(actual == expected)
        }
    }
// UIKit can't make a window in xctest, which runs package tests on Mac Catalyst without an
// NSApplication, so the iOS tests run on the iOS simulator alone.
#elseif os(iOS) && DEBUG && !targetEnvironment(macCatalyst)
    @testable import DebugDrawer
    import SwiftUI
    import Testing
    import UIKit

    // The SwiftPM test runner connects no window scene, so these tests use the overlay window on its
    // own, as it is made for a scene.
    @MainActor
    @Suite("Drawer overlay window")
    struct DrawerOverlayWindowTests {
        @Test("The overlay window takes no touch, sits above alerts and under the drawer's window, and is the drawer's own")
        func overlayTakesNoTouches() {
            let sut = DrawerOverlayWindow(scene: nil, content: Color.clear)
            sut.frame = CGRect(x: 0, y: 0, width: 400, height: 300)

            let actual = sut.hitTest(CGPoint(x: 50, y: 50), with: nil)

            #expect(actual == nil)
            #expect(sut.windowLevel > .alert)
            #expect(sut.windowLevel < DrawerSceneWindow.level)
            #expect(sut.rootViewController == nil)
            #expect(isDebugDrawerWindow(sut))
        }
    }
#endif
