// Views render on the Mac; the snapshot packages are linked on Apple platforms only.
#if os(macOS)
    import AppKit
    import SnapshotTesting
    import SwiftUI
    import Testing
    @testable import DebugDrawerTweaksPlugin

    // ImageRenderer draws AppKit-backed controls (text fields, pickers, switches, steppers) as
    // placeholders, so the tests host the view in a window that is never shown and draw it into a
    // bitmap at a fixed 2x scale, in the appearance the test asks for: the snapshot doesn't depend
    // on the Mac's own appearance or display. macOS doesn't scale text with Dynamic Type, so the Mac
    // pins light and dark only.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct TweaksSnapshotTests {
        @Test("Changed tweaks show their values and reset buttons, and Reset All is enabled", arguments: [ColorScheme.light, .dark])
        func changed(colorScheme: ColorScheme) throws {
            let sections = [
                TweakSection("Features") {
                    Tweak.toggle("New checkout", key: "newCheckout", default: false)
                    Tweak.text("Greeting", key: "greeting", default: "Welcome")
                },
                TweakSection("Server") {
                    Tweak.picker("Server", key: "server", default: Server.production)
                    Tweak.stepper("Timeout (s)", key: "timeout", default: 30, in: 5 ... 120, step: 5)
                },
                TweakSection("Session") {
                    TweakAction("Expire token") {}
                }
            ]
            let stored: [String: TweakStoredValue] = ["newCheckout": .bool(true), "server": .string("staging")]
            let sut = TweaksView(
                sections: sections.map { TweakSectionState($0, stored: { stored[$0] }) },
                onChange: { _, _ in },
                onReset: { _ in },
                onResetAll: {}
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

        @Test("Tweaks at their defaults show no reset buttons, and Reset All is disabled", arguments: [ColorScheme.light, .dark])
        func defaults(colorScheme: ColorScheme) throws {
            let sections = [
                TweakSection("Features") {
                    Tweak.toggle("New checkout", key: "newCheckout", default: false)
                    Tweak.stepper("Timeout (s)", key: "timeout", default: 30, in: 5 ... 120, step: 5)
                }
            ]
            let sut = TweaksView(
                sections: sections.map { TweakSectionState($0, stored: { _ in nil }) },
                onChange: { _, _ in },
                onReset: { _ in },
                onResetAll: {}
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
