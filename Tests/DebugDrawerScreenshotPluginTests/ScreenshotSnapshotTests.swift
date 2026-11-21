// Views render on the Mac; the snapshot packages are linked on Apple platforms only.
#if os(macOS)
    import AppKit
    import DebugDrawer
    import SnapshotTesting
    import SwiftUI
    import Testing
    @testable import DebugDrawerScreenshotPlugin

    // ImageRenderer draws AppKit-backed controls (text fields, pickers, switches, disclosure
    // groups) as placeholders, so a test of a view holding one hosts it in a window that is never
    // shown and draws it into a bitmap at a fixed 2x scale, in the appearance the test asks for:
    // the snapshot doesn't depend on the Mac's own appearance or display. Views without one use
    // ImageRenderer. macOS doesn't scale text with Dynamic Type, so the Mac pins light and dark only.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct ScreenshotSnapshotTests {
        @Test("Before a capture, the plugin shows the capture button and the hide-drawer switch", arguments: [ColorScheme.light, .dark])
        func ready(colorScheme: ColorScheme) throws {
            let model = ScreenshotModel(capturer: FakeScreenshotCapturer([]), saver: FakeScreenshotSaver())
            let sut = ScreenshotPluginView(transport: .direct(to: model))
            let host = NSHostingView(rootView: sut
                .frame(width: 320, alignment: .leading)
                .padding()
                .background(.background))
            host.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
            let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
            window.contentView = host
            host.frame = CGRect(origin: .zero, size: host.fittingSize)
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(host.bounds.width) * 2, pixelsHigh: Int(host.bounds.height) * 2,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            ))
            bitmap.size = host.bounds.size
            host.cacheDisplay(in: host.bounds, to: bitmap)

            let actual = NSImage(size: host.bounds.size)
            actual.addRepresentation(bitmap)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
        }

        @Test("With a capture held, the plugin shows the preview, the capture buttons and Clear", arguments: [ColorScheme.light, .dark])
        func held(colorScheme: ColorScheme) async throws {
            // A fixed window image: a gray title bar over a blue half and an orange half, 200 by 120
            // pixels at 2x, so the preview draws the same every run.
            let pattern = try #require(NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 200, pixelsHigh: 120, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            ))
            for row in 0 ..< 120 {
                for column in 0 ..< 200 {
                    let color = row < 20 ? NSColor(deviceRed: 0.55, green: 0.55, blue: 0.58, alpha: 1)
                        : column < 100 ? NSColor(deviceRed: 0.2, green: 0.45, blue: 0.9, alpha: 1)
                        : NSColor(deviceRed: 0.95, green: 0.6, blue: 0.2, alpha: 1)
                    pattern.setColor(color, atX: column, y: row)
                }
            }
            let png = try #require(pattern.representation(using: .png, properties: [:]))
            let image = ScreenshotImage(png: png, pixelWidth: 200, pixelHeight: 120, scale: 2)
            let transport = DebugDrawerPluginTransport.direct(to: ScreenshotModel(
                capturer: FakeScreenshotCapturer([.success(image)]), saver: FakeScreenshotSaver()
            ))
            transport.send(ScreenshotCommand(.capture))
            for await snapshot in transport.snapshots() where snapshot.status != .capturing {
                break
            }
            let sut = ScreenshotPluginView(transport: transport)
            let host = NSHostingView(rootView: sut
                .frame(width: 320, alignment: .leading)
                .padding()
                .background(.background))
            host.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
            let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
            window.contentView = host
            host.frame = CGRect(origin: .zero, size: host.fittingSize)
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(host.bounds.width) * 2, pixelsHigh: Int(host.bounds.height) * 2,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            ))
            bitmap.size = host.bounds.size
            host.cacheDisplay(in: host.bounds, to: bitmap)

            let actual = NSImage(size: host.bounds.size)
            actual.addRepresentation(bitmap)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
        }

        @Test("A capture saved to the Desktop shows Saved and its path above the preview", arguments: [ColorScheme.light, .dark])
        func saved(colorScheme: ColorScheme) async throws {
            // A fixed window image: a gray title bar over a blue half and an orange half, 200 by 120
            // pixels at 2x, so the preview draws the same every run.
            let pattern = try #require(NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 200, pixelsHigh: 120, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            ))
            for row in 0 ..< 120 {
                for column in 0 ..< 200 {
                    let color = row < 20 ? NSColor(deviceRed: 0.55, green: 0.55, blue: 0.58, alpha: 1)
                        : column < 100 ? NSColor(deviceRed: 0.2, green: 0.45, blue: 0.9, alpha: 1)
                        : NSColor(deviceRed: 0.95, green: 0.6, blue: 0.2, alpha: 1)
                    pattern.setColor(color, atX: column, y: row)
                }
            }
            let png = try #require(pattern.representation(using: .png, properties: [:]))
            let image = ScreenshotImage(png: png, pixelWidth: 200, pixelHeight: 120, scale: 2)
            let transport = DebugDrawerPluginTransport.direct(to: ScreenshotModel(
                capturer: FakeScreenshotCapturer([.success(image)]), saver: FakeScreenshotSaver(),
                appName: "Orders", now: { Date(timeIntervalSince1970: 1_800_000_000) }
            ))
            transport.send(ScreenshotCommand(.capture))
            transport.send(ScreenshotCommand(.save))
            for await snapshot in transport.snapshots() where snapshot.status != .capturing {
                break
            }
            let sut = ScreenshotPluginView(transport: transport)
            let host = NSHostingView(rootView: sut
                .frame(width: 320, alignment: .leading)
                .padding()
                .background(.background))
            host.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
            let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
            window.contentView = host
            host.frame = CGRect(origin: .zero, size: host.fittingSize)
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(host.bounds.width) * 2, pixelsHigh: Int(host.bounds.height) * 2,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            ))
            bitmap.size = host.bounds.size
            host.cacheDisplay(in: host.bounds, to: bitmap)

            let actual = NSImage(size: host.bounds.size)
            actual.addRepresentation(bitmap)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
        }
    }
#endif
