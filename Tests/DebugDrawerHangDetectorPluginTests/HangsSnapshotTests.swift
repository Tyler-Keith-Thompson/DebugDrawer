// Views render on the Mac; the snapshot packages are linked on Apple platforms only.
#if os(macOS)
    import AppKit
    @testable import DebugDrawerHangDetectorPlugin
    import SnapshotTesting
    import SwiftUI
    import Testing

    // ImageRenderer draws AppKit-backed controls (the picker, the buttons) as placeholders, so the
    // tests host the view in a window that is never shown and draw it into a bitmap at a fixed 2x
    // scale, in the appearance the test asks for: the snapshot doesn't depend on the Mac's own
    // appearance or display. macOS doesn't scale text with Dynamic Type, so the Mac pins light and
    // dark only. Dates are drawn in en_US and UTC, so the snapshot doesn't depend on the Mac's
    // settings.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct HangsSnapshotTests {
        @Test("Hangs list newest first under the threshold, an unread one dotted, the open one with its frames and Copy Report",
              arguments: [ColorScheme.light, .dark])
        func hangs(colorScheme: ColorScheme) throws {
            let opened = HangEvent(
                id: UUID(), date: Date(timeIntervalSince1970: 1_763_290_000), duration: .milliseconds(612),
                frames: [
                    "0 libsystem_kernel.dylib 0x00000001842b5f30 __semwait_signal + 8",
                    "1 libsystem_c.dylib 0x0000000184192e64 nanosleep + 220",
                    "2 libsystem_c.dylib 0x0000000184192d58 usleep + 68",
                    "3 Example 0x0000000100004a1c $s7Example13ExampleHangsO5blockyyFZ + 36",
                    "4 SwiftUI 0x00000001c2e1f2b4 $s7SwiftUI6ButtonV6actionyycvg + 28"
                ],
                source: .detected, isSeen: false
            )
            let older = HangEvent(
                id: UUID(), date: Date(timeIntervalSince1970: 1_763_289_000), duration: .milliseconds(1840),
                frames: [], source: .metricKit, isSeen: true
            )
            let sut = HangsView(
                events: [opened, older], threshold: .constant(.milliseconds(250)), expanded: .constant(opened.id), ownImage: "Example",
                onOpen: { _ in }, onMarkAllSeen: {}, onClear: {}
            )
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

        @Test("With no hangs the plugin shows the threshold and says when one will appear", arguments: [ColorScheme.light, .dark])
        func empty(colorScheme: ColorScheme) throws {
            let sut = HangsView(
                events: [], threshold: .constant(.milliseconds(250)), expanded: .constant(nil), onOpen: { _ in }, onMarkAllSeen: {}, onClear: {}
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
