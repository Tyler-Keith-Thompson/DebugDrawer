// The views are hosted on the Mac.
#if os(macOS)
    import AppKit
    import DebugDrawer
    @testable import DebugDrawerScreenRecordingPlugin
    import SwiftUI
    import Testing

    // The drawer is the process's one drawer, so the suite opens it and closes it again; nothing
    // else in this target reads whether it is open.
    @MainActor
    @Suite(.serialized)
    struct DrawerLeftOutTests {
        @Test(
            "With the drawer open, a recorded frame shows the app where the panel is, the right way up; the window as drawn shows the panel"
        )
        func drawerLeftOut() throws {
            DebugDrawer.shared.isOpen = true
            defer { DebugDrawer.shared.isOpen = false }
            // Green above, red below: a frame drawn upside down fails too.
            let content = VStack(spacing: 0) {
                Color.green.frame(height: 200)
                Color.red
            }
            .frame(width: 800, height: 600)
            .debugDrawer()
            let host = NSHostingView(rootView: content)
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = host
            host.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            CATransaction.flush()
            let layer = try #require(host.layer)
            let drawn = try #require(CGContext(
                data: nil, width: 800, height: 600, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            drawn.translateBy(x: 0, y: 600)
            drawn.scaleBy(x: 1, y: -1)
            layer.render(in: drawn)
            let onScreen = try #require(drawn.makeImage())
            let sut = try #require(RecordedWindows(window: window))

            let actual = try #require(sut.render(touches: []))

            /// The colour at `point` (in points from the top-leading corner) of `image`, drawn
            /// `scale` pixels a point: red, green and blue from 0 to 255.
            func color(of image: CGImage, at point: CGPoint, scale: CGFloat) -> [UInt8] {
                var pixel = [UInt8](repeating: 0, count: 4)
                pixel.withUnsafeMutableBytes { buffer in
                    let context = CGContext(
                        data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    )
                    let origin = CGPoint(x: -point.x * scale, y: -(CGFloat(image.height) - point.y * scale) + 1)
                    context?.draw(image, in: CGRect(origin: origin, size: CGSize(width: image.width, height: image.height)))
                }
                return Array(pixel.prefix(3))
            }
            func isRed(_ rgb: [UInt8]) -> Bool { rgb[0] > 200 && rgb[1] < 120 && rgb[2] < 120 }
            func isGreen(_ rgb: [UInt8]) -> Bool { rgb[1] > 150 && rgb[0] < 120 && rgb[2] < 150 }
            let scale = CGFloat(actual.width) / 800
            // The panel is 340 points wide at the trailing edge.
            let underPanel = CGPoint(x: 700, y: 400)
            let besidePanel = CGPoint(x: 100, y: 400)
            let topUnderPanel = CGPoint(x: 700, y: 100)
            #expect(isRed(color(of: actual, at: underPanel, scale: scale)))
            #expect(isRed(color(of: actual, at: besidePanel, scale: scale)))
            #expect(isGreen(color(of: actual, at: topUnderPanel, scale: scale)))
            #expect(!isRed(color(of: onScreen, at: underPanel, scale: 1)))
            #expect(isRed(color(of: onScreen, at: besidePanel, scale: 1)))
            #expect(!DrawerChromeLayers.layers(in: layer).isEmpty)
            #expect(DrawerChromeLayers.layers(in: layer).allSatisfy { !$0.isHidden })
        }
    }
#endif
