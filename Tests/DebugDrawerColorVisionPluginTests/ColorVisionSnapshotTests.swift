// Views render on the Mac; the snapshot packages are linked on Apple platforms only.
#if os(macOS)
    import AppKit
    @testable import DebugDrawerColorVisionPlugin
    import SnapshotTesting
    import SwiftUI
    import Testing

    // ImageRenderer draws AppKit-backed controls (the picker) as placeholders, so the plugin's views
    // are hosted in a window that is never shown and drawn into a bitmap at a fixed 2x scale, in the
    // appearance the test asks for: the snapshot doesn't depend on the Mac's own appearance or
    // display. macOS doesn't scale text with Dynamic Type, so the Mac pins light and dark only. The
    // simulated swatches are SwiftUI alone, and a hosted view's bitmap leaves SwiftUI's shaders
    // out, so ImageRenderer, which runs them, draws those.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct ColorVisionSnapshotTests {
        @Test("Off: the picker on Off, the app's own colors, and the footer", arguments: [ColorScheme.light, .dark])
        func off(colorScheme: ColorScheme) throws {
            let sut = ColorVisionView(simulation: .constant(nil))
            let host = NSHostingView(rootView: sut.frame(width: 320, alignment: .leading).padding().background(.background))
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

        @Test("Deuteranopia picked: its name in the picker and what it shows", arguments: [ColorScheme.light, .dark])
        func simulating(colorScheme: ColorScheme) throws {
            let sut = ColorVisionView(simulation: .constant(.deuteranopia))
            let host = NSHostingView(rootView: sut.frame(width: 320, alignment: .leading).padding().background(.background))
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

        @Test("The HUD while off and while simulating protanopia", arguments: [ColorScheme.light, .dark])
        func hud(colorScheme: ColorScheme) throws {
            let sut = VStack(alignment: .leading, spacing: 12) {
                ColorVisionHUDButton(simulation: nil, cycle: {})
                ColorVisionHUDButton(simulation: .protanopia, cycle: {})
            }
            let host = NSHostingView(rootView: sut.padding().background(.background))
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

        @Test("Swatches from red to pink, and a pass and a fail, under each simulation", arguments: ColorVision.Simulation.allCases)
        func swatches(simulation: ColorVision.Simulation) throws {
            let renderer = ImageRenderer(content: ColorVisionSwatchFixture().colorVisionSimulation(simulation))
            renderer.scale = 2

            let image = try #require(renderer.cgImage)
            let actual = NSImage(cgImage: image, size: CGSize(width: 240, height: 96))

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: simulation.rawValue)
        }

        @Test("Swatches from red to pink, and a pass and a fail, with no simulation")
        func swatchesOff() throws {
            let renderer = ImageRenderer(content: ColorVisionSwatchFixture().colorVisionSimulation(nil))
            renderer.scale = 2

            let image = try #require(renderer.cgImage)
            let actual = NSImage(cgImage: image, size: CGSize(width: 240, height: 96))

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "off")
        }
    }
#endif
