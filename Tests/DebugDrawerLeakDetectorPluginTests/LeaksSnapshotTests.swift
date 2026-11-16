// Views render on the Mac; the snapshot packages are linked on Apple platforms only.
#if os(macOS)
    import AppKit
    @testable import DebugDrawerLeakDetectorPlugin
    import SnapshotTesting
    import SwiftUI
    import Testing

    // ImageRenderer draws AppKit-backed controls (the buttons) as placeholders, so the tests host
    // the view in a window that is never shown and draw it into a bitmap at a fixed 2x scale, in
    // the appearance the test asks for: the snapshot doesn't depend on the Mac's own appearance or
    // display. macOS doesn't scale text with Dynamic Type, so the Mac pins light and dark only.
    // Dates are drawn in en_US and UTC, so the snapshot doesn't depend on the Mac's settings.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct LeaksSnapshotTests {
        @Test("Suspects list newest first, each with its class, count, kind, date and Ignore, then the ignored count",
              arguments: [ColorScheme.light, .dark])
        func suspects(colorScheme: ColorScheme) throws {
            let suspects = [
                LeakSuspect(
                    type: TrackedClass(name: "ProfileViewController", qualifiedName: "Example.ProfileViewController"),
                    reason: .aliveAfterDismissal, count: 2, since: Date(timeIntervalSince1970: 1_763_290_000)
                ),
                LeakSuspect(
                    type: TrackedClass(name: "ProfileModel", qualifiedName: "Example.ProfileModel"),
                    reason: .overLimit(maxCount: 1), count: 3, since: Date(timeIntervalSince1970: 1_763_289_000)
                )
            ]
            let sut = LeaksView(suspects: suspects, ignoredCount: 1, onIgnore: { _ in }, onStopIgnoring: {})
            let host = NSHostingView(rootView: sut
                .environment(\.locale, Locale(identifier: "en_US"))
                .environment(\.timeZone, try #require(TimeZone(identifier: "UTC")))
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

        @Test("With no suspects the plugin says what would appear", arguments: [ColorScheme.light, .dark])
        func empty(colorScheme: ColorScheme) throws {
            let sut = LeaksView(suspects: [], ignoredCount: 0, onIgnore: { _ in }, onStopIgnoring: {})
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
