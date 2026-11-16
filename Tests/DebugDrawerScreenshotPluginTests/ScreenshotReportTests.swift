// AppKit capture runs on the Mac.
#if os(macOS)
    import AppKit
    import DebugDrawer
    @testable import DebugDrawerScreenshotPlugin
    import SwiftUI
    import Testing

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct ScreenshotReportTests {
        @Test("The report gets screenshot.png, the window's content as a PNG")
        func windowAsPNG() throws {
            let host = NSHostingView(rootView: Color.red.frame(width: 40, height: 30))
            host.frame = NSRect(x: 0, y: 0, width: 40, height: 30)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            var actual = DebugDrawerReport()

            ScreenshotPlugin.contribute(capturing: window, to: &actual)

            let file = try #require(actual.files.first)
            let image = try #require(NSBitmapImageRep(data: file.data))
            #expect(file.name == "screenshot.png")
            #expect(file.kind == .png)
            #expect(file.data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
            #expect(image.pixelsWide == Int(40 * window.backingScaleFactor))
            #expect(image.pixelsHigh == Int(30 * window.backingScaleFactor))
        }

        @Test("With no window, the report gets nothing")
        func noWindow() {
            var actual = DebugDrawerReport()

            ScreenshotPlugin.contribute(capturing: nil, to: &actual)

            #expect(actual.files.isEmpty)
        }
    }
#endif
