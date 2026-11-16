// AppKit capture runs on the Mac.
#if os(macOS)
    import AppKit
    @testable import DebugDrawerScreenshotPlugin
    import SwiftUI
    import Testing

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct WindowCaptureTests {
        @Test("A capture is the view's size in points times the scale, in pixels")
        func pixelSize() throws {
            let host = NSHostingView(rootView: Color.red.frame(width: 120, height: 80))
            host.frame = NSRect(x: 0, y: 0, width: 120, height: 80)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            host.layoutSubtreeIfNeeded()

            let actual = try #require(WindowCapture.bitmap(of: host, scale: 2))

            #expect(actual.pixelsWide == 240)
            #expect(actual.pixelsHigh == 160)
            #expect(actual.size == NSSize(width: 120, height: 80))
        }

        @Test("A capture draws the window's own content, with no screen capture")
        func drawsContent() throws {
            let host = NSHostingView(rootView: Color(red: 1, green: 0, blue: 0).frame(width: 40, height: 40))
            host.frame = NSRect(x: 0, y: 0, width: 40, height: 40)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            host.layoutSubtreeIfNeeded()

            let bitmap = try #require(WindowCapture.bitmap(of: host, scale: 1))
            let actual = try #require(bitmap.colorAt(x: 20, y: 20)?.usingColorSpace(.sRGB))

            #expect(actual.redComponent > 0.9)
            #expect(actual.greenComponent < 0.1)
            #expect(actual.blueComponent < 0.1)
        }

        @Test("A view with no area has no capture")
        func emptyView() {
            let view = NSView(frame: .zero)

            let actual = WindowCapture.bitmap(of: view, scale: 2)

            #expect(actual == nil)
        }
    }
#endif
