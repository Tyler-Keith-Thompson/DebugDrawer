// Views render on the Mac; the snapshot packages are linked on Apple platforms only.
#if os(macOS)
    import AppKit
    @testable import DebugDrawerLocationPlugin
    import SnapshotTesting
    import SwiftUI
    import Testing

    // The section holds menus, which AppKit draws and ImageRenderer leaves as placeholders, so each
    // test hosts it in a window that is never shown and draws it into a bitmap at a fixed 2x scale,
    // in the appearance the test asks for, at the drawer's 316 pt content width. macOS doesn't scale
    // text with Dynamic Type, so the Mac pins light and dark only.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct RouteSnapshotTests {
        @Test("Stopped, the Route section shows the track and speed menus, no point delivered, and Play", arguments: [ColorScheme.light, .dark])
        func idle(colorScheme: ColorScheme) throws {
            let sut = RouteSection(
                routes: Route.samples, selection: .constant("sample:Apple Park Loop"), speed: .constant(.times1), playback: .stopped,
                importFailure: nil, actions: RouteActions()
            )
            let host = NSHostingView(rootView: sut
                .frame(width: 316, alignment: .leading)
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

        @Test("Playing at 5x, the Route section shows the point reached and its track time, and Pause", arguments: [ColorScheme.light, .dark])
        func playing(colorScheme: ColorScheme) throws {
            let sut = RouteSection(
                routes: Route.samples, selection: .constant("sample:Apple Park Loop"), speed: .constant(.times5),
                playback: .playing(delivered: 7), importFailure: nil, actions: RouteActions()
            )
            let host = NSHostingView(rootView: sut
                .frame(width: 316, alignment: .leading)
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

        @Test("A file that couldn't be played shows why, under the progress", arguments: [ColorScheme.light, .dark])
        func importFailure(colorScheme: ColorScheme) throws {
            let sut = RouteSection(
                routes: Route.samples, selection: .constant("sample:Apple Park Loop"), speed: .constant(.times1), playback: .stopped,
                importFailure: .notGPX, actions: RouteActions()
            )
            let host = NSHostingView(rootView: sut
                .frame(width: 316, alignment: .leading)
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
