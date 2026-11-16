// Views render on the Mac; the snapshot packages are linked on Apple platforms only.
#if os(macOS)
    import AppKit
    import SnapshotTesting
    import SwiftUI
    import Testing
    @testable import DebugDrawerLocationPlugin

    // ImageRenderer draws AppKit-backed controls (text fields, pickers, switches, disclosure
    // groups) as placeholders, so a test of a view holding one hosts it in a window that is never
    // shown and draws it into a bitmap at a fixed 2x scale, in the appearance the test asks for:
    // the snapshot doesn't depend on the Mac's own appearance or display. Views without one use
    // ImageRenderer. macOS doesn't scale text with Dynamic Type, so the Mac pins light and dark only.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct LocationSnapshotTests {
        @Test("With spoofing off, the form shows only the switch that turns it on", arguments: [ColorScheme.light, .dark])
        func off(colorScheme: ColorScheme) throws {
            let sut = LocationForm(
                isEnabled: .constant(false), latitudeText: .constant(""), longitudeText: .constant(""),
                active: nil, presets: [], onPreset: { _ in }
            )
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

        @Test("With spoofing on, the form shows the coordinate fields, the location in effect and the presets", arguments: [ColorScheme.light, .dark])
        func on(colorScheme: ColorScheme) throws {
            let presets = [
                LocationSimulator.PresetLocation(name: "Cupertino", latitude: 37.3349, longitude: -122.009),
                LocationSimulator.PresetLocation(name: "London", latitude: 51.5074, longitude: -0.1278)
            ]
            let sut = LocationForm(
                isEnabled: .constant(true), latitudeText: .constant("37.3349"), longitudeText: .constant("-122.009"),
                active: .init(latitude: 37.3349, longitude: -122.009), presets: presets, onPreset: { _ in }
            )
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
