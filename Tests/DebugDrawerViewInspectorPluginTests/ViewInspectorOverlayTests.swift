// Borders, ripples and the grid are drawn in the drawer's overlay window, never in the app's: these
// pin that the app's views keep every layer property and draw exactly as before while they are on.
// Each test makes its own controller over a window it never shows, so no window reaches the
// screen and the shared controller is left alone.
#if os(macOS) && DEBUG
    import AppKit
    @testable import DebugDrawer
    @testable import DebugDrawerViewInspectorPlugin
    import SwiftUI
    import Testing

    @MainActor
    @Suite
    struct ViewInspectorOverlayTests {
        @Test("Turning borders on and off leaves every layer property of the app's views as it was, for a view without a layer too")
        func bordersLeaveHostLayersUnchanged() throws {
            func properties(of view: NSView) -> String {
                let layer = view.layer
                return "\(view.wantsLayer) \(layer.map { ObjectIdentifier($0).debugDescription } ?? "no layer") "
                    + "\(layer?.borderWidth ?? -1) \(layer?.borderColor.map { String(describing: $0) } ?? "no color") "
                    + "\(layer?.cornerRadius ?? -1) \(layer?.masksToBounds ?? false)"
            }
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 320, height: 200), styleMask: [.titled], backing: .buffered, defer: true)
            let content = NSView(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
            let bordered = NSView(frame: CGRect(x: 20, y: 20, width: 120, height: 80))
            bordered.wantsLayer = true
            let layer = try #require(bordered.layer)
            layer.borderWidth = 3
            layer.borderColor = NSColor.systemRed.cgColor
            layer.cornerRadius = 6
            let plain = NSView(frame: CGRect(x: 180, y: 20, width: 120, height: 80))
            content.addSubview(bordered)
            content.addSubview(plain)
            window.contentView = content
            let expected = [content, bordered, plain].map(properties)
            let expectedOutlines = 3
            let sut = ViewBorderController(appWindows: { [window] })

            sut.isBordersEnabled = true
            sut.refreshOverlays()
            let outlines = sut.overlays.existing(over: window)?.model.outlines.count
            sut.isBordersEnabled = false
            let actual = [content, bordered, plain].map(properties)

            #expect(actual == expected)
            #expect(outlines == expectedOutlines)
            #expect(!plain.wantsLayer)
            #expect(sut.overlays.existing(over: window) == nil)
        }

        @Test("With borders and click indicators on, the app's window draws exactly what it draws with them off")
        func hostWindowDrawsTheSame() throws {
            func render(_ view: NSView) throws -> Data {
                let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                view.cacheDisplay(in: view.bounds, to: bitmap)
                return try #require(bitmap.tiffRepresentation)
            }
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 320, height: 200), styleMask: [.titled], backing: .buffered, defer: true)
            let content = NSView(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
            content.wantsLayer = true
            content.layer?.backgroundColor = NSColor.white.cgColor
            let card = NSView(frame: CGRect(x: 20, y: 20, width: 120, height: 80))
            card.wantsLayer = true
            card.layer?.backgroundColor = NSColor.systemTeal.cgColor
            content.addSubview(card)
            window.contentView = content
            let expected = try render(content)
            let sut = ViewBorderController(appWindows: { [window] })

            sut.isBordersEnabled = true
            sut.isClickIndicatorEnabled = true
            sut.refreshOverlays()
            sut.showRipple(at: CGPoint(x: 60, y: 60), in: window)
            let actual = try render(content)
            let model = sut.overlays.existing(over: window)?.model
            let outlines = model?.outlines.count
            let ripples = model?.ripples.count
            sut.isBordersEnabled = false
            sut.isClickIndicatorEnabled = false

            #expect(actual == expected)
            #expect(content.subviews == [card])
            #expect(outlines == 2)
            #expect(ripples == 1)
        }

        @Test("A view added while borders are on is outlined on the next refresh, in the overlay's top-leading coordinates")
        func outlinesFollowTheHierarchy() throws {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 320, height: 200), styleMask: [.titled], backing: .buffered, defer: true)
            let content = NSView(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
            window.contentView = content
            let sut = ViewBorderController(appWindows: { [window] })
            sut.isBordersEnabled = true
            sut.refreshOverlays()
            let pushed = NSView(frame: CGRect(x: 10, y: 20, width: 100, height: 40))
            // 20 pt up from the bottom of a 200 pt view, 40 tall: 140 down from its top.
            let expected = [
                ViewOutline(frame: CGRect(x: 0, y: 0, width: 320, height: 200), depth: 0),
                ViewOutline(frame: CGRect(x: 10, y: 140, width: 100, height: 40), depth: 1)
            ]

            content.addSubview(pushed)
            sut.refreshOverlays()
            let actual = sut.overlays.existing(over: window)?.model.outlines
            sut.isBordersEnabled = false

            #expect(actual == expected)
        }

        @Test("Borders keep no app view alive: a view removed while they are on is freed")
        func bordersHoldNoViews() {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 320, height: 200), styleMask: [.titled], backing: .buffered, defer: true)
            let content = NSView(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
            window.contentView = content
            let sut = ViewBorderController(appWindows: { [window] })
            weak var removed: NSView?
            // Each step drains its own autorelease pool, so AppKit's autoreleased references
            // don't keep the view alive past it.
            autoreleasepool {
                let view = NSView(frame: CGRect(x: 10, y: 10, width: 50, height: 50))
                content.addSubview(view)
                removed = view
            }

            sut.isBordersEnabled = true
            autoreleasepool { sut.refreshOverlays() }
            autoreleasepool { removed?.removeFromSuperview() }
            autoreleasepool { sut.refreshOverlays() }
            let actual = removed
            sut.isBordersEnabled = false

            #expect(actual == nil)
        }

        @Test("The drawer's own windows are never outlined or slowed: the app's windows leave them out")
        func drawerWindowsAreLeftOut() {
            let host = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 320, height: 200), styleMask: [.titled], backing: .buffered, defer: true)
            let overlay = DrawerOverlayWindow(over: host, content: Color.clear)

            let actual = ViewBorderController.visibleAppWindows()

            #expect(!actual.contains(overlay))
            #expect(isDebugDrawerWindow(overlay))
        }
    }

// UIKit can't make a window in xctest, which runs package tests on Mac Catalyst without an
// NSApplication, so the iOS tests run on the iOS simulator alone.
#elseif os(iOS) && DEBUG && !targetEnvironment(macCatalyst)
    @testable import DebugDrawer
    @testable import DebugDrawerViewInspectorPlugin
    import Testing
    import UIKit

    // The SwiftPM test runner connects no window scene, so no overlay window is made here; these pin
    // that nothing is written to the app's views.
    @MainActor
    @Suite
    struct ViewInspectorOverlayTests {
        @Test("Turning borders on and off leaves every layer property of the app's views as it was")
        func bordersLeaveHostLayersUnchanged() {
            func properties(of view: UIView) -> String {
                let layer = view.layer
                return "\(layer.borderWidth) \(layer.borderColor.map { String(describing: $0) } ?? "no color") "
                    + "\(layer.cornerRadius) \(layer.masksToBounds) \(view.subviews.count)"
            }
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
            let bordered = UIView(frame: CGRect(x: 20, y: 20, width: 120, height: 80))
            bordered.layer.borderWidth = 3
            bordered.layer.borderColor = UIColor.systemRed.cgColor
            bordered.layer.cornerRadius = 6
            let plain = UIView(frame: CGRect(x: 180, y: 20, width: 120, height: 80))
            window.addSubview(bordered)
            window.addSubview(plain)
            let expected = [window, bordered, plain].map(properties)
            let sut = ViewBorderController(appWindows: { [window] })

            sut.isBordersEnabled = true
            sut.refreshOverlays()
            sut.isBordersEnabled = false
            let actual = [window, bordered, plain].map(properties)

            #expect(actual == expected)
        }

        @Test("A window's views are outlined in another window's coordinates, the window first, hidden views left out")
        func outlinesAreRead() {
            // Inside the test host (Bazel) both windows join its scene, since there UIKit converts
            // nothing between windows that have none; SwiftPM's runner connects no scene.
            func makeWindow() -> UIWindow {
                let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
                let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow()
                window.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
                return window
            }
            let window = makeWindow()
            let overlay = makeWindow()
            let card = UIView(frame: CGRect(x: 20, y: 30, width: 120, height: 80))
            let hidden = UIView(frame: CGRect(x: 180, y: 20, width: 120, height: 80))
            hidden.isHidden = true
            window.addSubview(card)
            window.addSubview(hidden)
            let expected = [
                ViewOutline(frame: CGRect(x: 0, y: 0, width: 320, height: 200), depth: 0),
                ViewOutline(frame: CGRect(x: 20, y: 30, width: 120, height: 80), depth: 1)
            ]

            let actual = ViewOutline.read(from: [window], in: overlay)

            #expect(actual == expected)
        }
    }
#endif
