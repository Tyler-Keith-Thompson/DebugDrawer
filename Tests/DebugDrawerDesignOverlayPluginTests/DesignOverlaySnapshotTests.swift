// Views render on the Mac; the snapshot packages are linked on Apple platforms only.
#if os(macOS)
    import AppKit
    @testable import DebugDrawerDesignOverlayPlugin
    import SnapshotTesting
    import SwiftUI
    import Testing

    // ImageRenderer draws AppKit-backed controls (the switches, the slider, the pickers, the
    // steppers) as placeholders, so the plugin's views are hosted in a window that is never shown
    // and drawn into a bitmap at a fixed 2x scale, in the appearance the test asks for: the snapshot
    // doesn't depend on the Mac's own appearance or display. macOS doesn't scale text with Dynamic
    // Type, so the Mac pins light and dark only. The mockup over the app is SwiftUI alone, an image
    // over shapes, so ImageRenderer draws it, blend included.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct DesignOverlaySnapshotTests {
        @Test("Before a mockup: where to pick one, then Choose File… and Paste", arguments: [ColorScheme.light, .dark])
        func empty(colorScheme: ColorScheme) throws {
            let sut = DesignOverlayView(
                mockup: nil, failure: nil, windowWidth: 430, settings: .constant(DesignOverlaySettings()), isMoving: .constant(false),
                sources: .none, clear: {}
            )
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

        @Test(
            "A @3x mockup: its sizes and thumbnail, Show on, 60% in Difference, automatic scale, moved 12 by -4, Reset Position and Clear",
            arguments: [ColorScheme.light, .dark]
        )
        func showing(colorScheme: ColorScheme) throws {
            let mockup = try Mockup(data: MockupFixture.png(width: 1290, height: 2796))
            var settings = DesignOverlaySettings()
            settings.opacity = 0.6
            settings.blend = .difference
            settings.offset = CGSize(width: 12, height: -4)
            let sut = DesignOverlayView(
                mockup: mockup, failure: nil, windowWidth: 430, settings: .constant(settings), isMoving: .constant(false),
                sources: .none, clear: {}
            )
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

        @Test("The HUD while the mockup shows and while Move is on, above the Move bar", arguments: [ColorScheme.light, .dark])
        func hudAndMoveBar(colorScheme: ColorScheme) throws {
            let sut = VStack(alignment: .leading, spacing: 12) {
                DesignOverlayHUDButtons(state: .showing(opacity: "50%", blend: .normal), toggleVisibility: {}, endMoving: {})
                DesignOverlayHUDButtons(state: .moving, toggleVisibility: {}, endMoving: {})
                MoveModeBar(offset: CGSize(width: 12, height: -4), done: {})
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

        @Test(
            "Over content that drifts from the comp (button 6 points right, second row shorter): 50% normal, and opaque Difference",
            arguments: [MockupBlend.normal, .difference]
        )
        func composite(blend: MockupBlend) throws {
            // The fixture's layout in points, at 200 by 300: the comp is the same drawn at @2x.
            let content = ZStack(alignment: .topLeading) {
                Color(red: 0.95, green: 0.95, blue: 0.97)
                Color(red: 0.20, green: 0.45, blue: 0.95).frame(width: 200, height: 42)
                Color(red: 0.95, green: 0.30, blue: 0.45).frame(width: 80, height: 30).offset(x: 26, y: 66)
                Color(red: 0.80, green: 0.82, blue: 0.86).frame(width: 160, height: 24).offset(x: 20, y: 120)
                Color(red: 0.80, green: 0.82, blue: 0.86).frame(width: 120, height: 24).offset(x: 20, y: 162)
                Color(red: 0.80, green: 0.82, blue: 0.86).frame(width: 160, height: 24).offset(x: 20, y: 204)
            }
            .frame(width: 200, height: 300)
            let mockup = try Mockup(data: MockupFixture.png(width: 400, height: 600))
            var settings = DesignOverlaySettings()
            settings.blend = blend
            settings.opacity = blend == .difference ? 1 : 0.5
            let sut = content.overlay { DesignOverlayLayer(mockup: mockup, settings: settings, isMoving: false, move: { _ in }) }
            let renderer = ImageRenderer(content: sut)
            renderer.scale = 2

            let image = try #require(renderer.cgImage)
            let actual = NSImage(cgImage: image, size: CGSize(width: 200, height: 300))

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: blend.rawValue)
        }
    }
#endif
