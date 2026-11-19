// Views render on the Mac; the snapshot packages are linked on Apple platforms only.
#if os(macOS)
    import AppKit
    @testable import DebugDrawerCrashReportsPlugin
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
    struct CrashReportsSnapshotTests {
        @Test("Reports list newest first, an unread one dotted, the open one with its frames (the app's first selected), Copy Report and Delete",
              arguments: [ColorScheme.light, .dark])
        func reports(colorScheme: ColorScheme) throws {
            let opened = CrashReport(
                id: UUID(), date: Date(timeIntervalSince1970: 1_763_290_000), title: "SIGTRAP",
                reason: "Trap: a Swift runtime failure, such as unwrapping nil or an index out of range", appVersion: "1.2 (34)",
                frames: [
                    "0 libswiftCore.dylib 0x000000018f2b1a40 $ss17_assertionFailure__4file4line5flagss5NeverOs12StaticStringV_A2HSus6UInt32VtF + 172",
                    "1   Example              0x0000000100004a1c $s7Example11ContentViewV5crashyyF + 48",
                    "2   SwiftUI              0x00000001c2e1f2b4 $s7SwiftUI6ButtonV6actionyycvg + 28"
                ],
                source: .captured, isSeen: false
            )
            let older = CrashReport(
                id: UUID(), date: Date(timeIntervalSince1970: 1_763_200_000), title: "NSInvalidArgumentException",
                reason: "*** -[__NSArrayI objectAtIndex:]: index 5 beyond bounds [0 .. 2]", appVersion: "1.2 (33)",
                frames: [], source: .metricKit, isSeen: true
            )
            let sut = CrashReportsView(
                reports: [opened, older], expanded: .constant(opened.id), ownImage: "Example",
                onOpen: { _ in }, onDelete: { _ in }, onMarkAllSeen: {}, onDeleteAll: {}
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

        @Test("With no reports the plugin says where one will appear", arguments: [ColorScheme.light, .dark])
        func empty(colorScheme: ColorScheme) throws {
            let sut = CrashReportsView(
                reports: [], expanded: .constant(nil), onOpen: { _ in }, onDelete: { _ in }, onMarkAllSeen: {}, onDeleteAll: {}
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
