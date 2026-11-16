// Views render on the Mac; the snapshot packages are linked on Apple platforms only.
#if os(macOS)
    import AppKit
    import SnapshotTesting
    import SwiftUI
    import Testing
    @testable import DebugDrawerFeatureFlagsPlugin

    // ImageRenderer draws AppKit-backed controls (text fields, switches) as placeholders, so the
    // tests host the view in a window that is never shown and draw it into a bitmap at a fixed 2x
    // scale, in the appearance the test asks for: the snapshot doesn't depend on the Mac's own
    // appearance or display. macOS doesn't scale text with Dynamic Type, so the Mac pins light and
    // dark only.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct FeatureFlagsSnapshotTests {
        @Test("Flags show their controls, keys and live values, overridden ones tagged with a clear button", arguments: [ColorScheme.light, .dark])
        func flags(colorScheme: ColorScheme) throws {
            let rows = [
                FeatureFlagRowState(
                    FeatureFlag(key: "new-checkout", liveValue: .bool(false), title: "New checkout", detail: "The one-page payment sheet"),
                    currentValue: .bool(true),
                    override: .bool(true)
                ),
                FeatureFlagRowState(
                    FeatureFlag(key: "discount", liveValue: .number(0.1), title: "Discount"),
                    currentValue: .number(0.1),
                    override: nil
                ),
                FeatureFlagRowState(FeatureFlag(key: "theme", liveValue: .string("light")), currentValue: .string("dark"), override: .string("dark"))
            ]
            let sut = FeatureFlagsView(
                rows: rows, overrideCount: 2, query: .constant(""), isOverriddenOnly: .constant(false),
                onOverride: { _, _ in }, onClear: { _ in }, onClearAll: {}, onRefresh: {}
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

        @Test("With only overridden flags shown and none overridden, the list says so and Reset All is disabled",
              arguments: [ColorScheme.light, .dark])
        func noneOverridden(colorScheme: ColorScheme) throws {
            let rows = [
                FeatureFlagRowState(
                    FeatureFlag(key: "discount", liveValue: .number(0.1), title: "Discount"),
                    currentValue: .number(0.1),
                    override: nil
                )
            ]
            let sut = FeatureFlagsView(
                rows: rows, overrideCount: 0, query: .constant(""), isOverriddenOnly: .constant(true),
                onOverride: { _, _ in }, onClear: { _ in }, onClearAll: {}, onRefresh: {}
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
