// Views render on the Mac; the snapshot packages are linked on Apple platforms only.
#if os(macOS)
    import AppKit
    @testable import DebugDrawerMetricKitPlugin
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
    struct MetricKitPayloadsSnapshotTests {
        @Test("Payloads list the latest first, a new one tagged, the open one with its JSON and its copy and export buttons",
              arguments: [ColorScheme.light, .dark])
        func payloads(colorScheme: ColorScheme) throws {
            let opened = MetricKitPayload(
                id: UUID(), kind: .diagnostics, begin: Date(timeIntervalSince1970: 1_763_290_000), end: Date(timeIntervalSince1970: 1_763_290_000),
                received: Date(timeIntervalSince1970: 1_763_290_000),
                json: Data("""
                {
                  "hangDiagnostics": [{"diagnosticMetaData": {"appVersion": "1.2", "hangDuration": "2.1 sec", "osVersion": "iPhone OS 26.1"}}],
                  "timeStampBegin": "2025-11-16 10:46:40 +0000",
                  "timeStampEnd": "2025-11-16 10:46:40 +0000"
                }
                """.utf8),
                isSeen: false
            )
            let metrics = MetricKitPayload(
                id: UUID(), kind: .metrics, begin: Date(timeIntervalSince1970: 1_763_164_800), end: Date(timeIntervalSince1970: 1_763_251_200),
                received: Date(timeIntervalSince1970: 1_763_254_000),
                json: Data("""
                {
                  "appVersion": "1.2", "metaData": {"appBuildVersion": "34"},
                  "cpuMetrics": {}, "diskIOMetrics": {}, "memoryMetrics": {}, "applicationLaunchMetrics": {}
                }
                """.utf8),
                isSeen: true
            )
            let sut = MetricKitPayloadsView(
                payloads: [opened, metrics], expanded: .constant(opened.id),
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

        @Test("With no payloads the plugin says when they arrive", arguments: [ColorScheme.light, .dark])
        func empty(colorScheme: ColorScheme) throws {
            let sut = MetricKitPayloadsView(
                payloads: [], expanded: .constant(nil), onOpen: { _ in }, onDelete: { _ in }, onMarkAllSeen: {}, onDeleteAll: {}
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
