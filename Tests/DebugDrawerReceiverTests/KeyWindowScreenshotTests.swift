#if os(macOS)
    import AppKit
    @testable import DebugDrawerReceiver
    import Testing

    // A bug report's screenshot drawn from a window of the test's own, never shown: the app draws
    // its own window, so no screen capture and no permission is involved.
    @MainActor
    @Suite
    struct KeyWindowScreenshotTests {
        /// A window, never shown, whose content is a 120 by 80 point red view.
        private func makeWindow() -> NSWindow {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 120, height: 80), styleMask: [.borderless], backing: .buffered, defer: false)
            let view = NSView(frame: NSRect(x: 0, y: 0, width: 120, height: 80))
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor.red.cgColor
            window.contentView = view
            return window
        }

        @Test("A window is drawn as PNG at its backing scale when it fits the bound")
        func drawsWindow() throws {
            let window = makeWindow()
            let expectedWidth = Int((120 * window.backingScaleFactor).rounded())

            let actual = KeyWindowScreenshot.capture(window, maximumBytes: 4 << 20)

            guard case let .png(data) = actual else {
                Issue.record("No PNG: \(actual)")
                return
            }
            let image = try #require(NSBitmapImageRep(data: data))
            #expect(image.pixelsWide == expectedWidth)
            #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        }

        @Test("A window that doesn't fit even at one pixel per point is left out with its size")
        func tooLarge() {
            let window = makeWindow()

            let actual = KeyWindowScreenshot.capture(window, maximumBytes: 1)

            guard case let .tooLarge(byteCount) = actual else {
                Issue.record("Not left out: \(actual)")
                return
            }
            #expect(byteCount > 1)
        }

        @Test("A window with no content view draws nothing: unavailable")
        func noContent() {
            let window = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: true)
            window.contentView = nil

            let actual = KeyWindowScreenshot.capture(window, maximumBytes: 4 << 20)

            #expect(actual == .unavailable)
        }
    }
#endif
