// Views render on the Mac; the snapshot packages are linked on Apple platforms only.
#if os(macOS)
    import AppKit
    @testable import DebugDrawerLocalizationPlugin
    import SnapshotTesting
    import SwiftUI
    import Testing

    // ImageRenderer draws AppKit-backed controls (the switches, the picker, the filter field) as
    // placeholders, so the tests host the view in a window that is never shown and draw it into a
    // bitmap at a fixed 2x scale, in the appearance the test asks for: the snapshot doesn't depend
    // on the Mac's own appearance or display. macOS doesn't scale text with Dynamic Type, so the
    // Mac pins light and dark only. Language names are drawn in en_US.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct LocalizationSnapshotTests {
        @Test(
            "Pseudo-localizing: the sample, then German's missing translations by table, one looked up, Copy and Refresh, then the launch arguments",
            arguments: [ColorScheme.light, .dark]
        )
        func missing(colorScheme: ColorScheme) throws {
            let bundle = LocalizedBundle(
                name: "DebugDrawerExample.app", path: "/App.app", isMain: true, developmentLocalization: "en", preferredLocalization: "de",
                tables: [
                    "en": [
                        LocalizationTable(name: "Localizable", entries: [
                            "welcome.title": LocalizationEntry("Welcome back"),
                            "settings.privacy": LocalizationEntry("Privacy Policy"),
                            "orders.count": LocalizationEntry("%lld orders", isPlural: true)
                        ]),
                        LocalizationTable(name: "Checkout", entries: [
                            "checkout.promo": LocalizationEntry("Have a promo code?"),
                            "checkout.delivery": LocalizationEntry("Delivery: %@")
                        ])
                    ],
                    "de": [
                        LocalizationTable(name: "Localizable", entries: [
                            "welcome.title": LocalizationEntry("Willkommen zurück"),
                            "orders.count": LocalizationEntry("%lld Bestellungen", isPlural: true)
                        ])
                    ]
                ]
            )
            let lookups = [LocalizationLookup(bundlePath: "/App.app", table: nil, key: "banner.new", defaultValue: "New: faster checkout")]
            let sut = LocalizationView(
                mode: .constant(.pseudoLocalized), bundles: [bundle], lookups: lookups,
                nextLaunch: [.pseudoLocalized], launchedWith: [], onRefresh: {}
            )
            let host = NSHostingView(rootView: sut
                .environment(\.locale, Locale(identifier: "en_US"))
                .frame(width: 320, alignment: .leading)
                .padding()
                .background(.background))
            host.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
            let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
            window.contentView = host
            // The list scrolls once it is taller than its limit, so its fitting height is less
            // than its rows'; the fixture is given the height that shows every row.
            host.frame = CGRect(origin: .zero, size: CGSize(width: host.fittingSize.width, height: host.fittingSize.height + 16))
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

        @Test("An app in one language: both modes off, a note that nothing can be missing, then the launch arguments",
              arguments: [ColorScheme.light, .dark])
        func singleLanguage(colorScheme: ColorScheme) throws {
            let bundle = LocalizedBundle(
                name: "DebugDrawerExample.app", path: "/App.app", isMain: true, developmentLocalization: "en", preferredLocalization: "en",
                tables: ["en": [LocalizationTable(name: "Localizable", entries: ["welcome.title": LocalizationEntry("Welcome back")])]]
            )
            let sut = LocalizationView(mode: .constant(.standard), bundles: [bundle], lookups: [], onRefresh: {})
            let host = NSHostingView(rootView: sut
                .environment(\.locale, Locale(identifier: "en_US"))
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
