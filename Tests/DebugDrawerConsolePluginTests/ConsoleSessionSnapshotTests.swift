// Views render on the Mac; the snapshot packages are linked on Apple platforms only.
#if os(macOS)
    import AppKit
    import DebugDrawer
    @testable import DebugDrawerConsolePlugin
    import SnapshotTesting
    import SwiftUI
    import Testing

    // At 316 points, the width of the drawer on an iPad and the narrowest it gets. The controls
    // hold segmented and menu pickers, which ImageRenderer draws as placeholders, so they are
    // hosted in a window that is never shown and drawn into a bitmap at a fixed 2x scale, in the
    // appearance the test asks for. macOS doesn't scale text with Dynamic Type, so the Mac pins
    // light and dark only. The time zone is fixed, so the session's start reads the same anywhere.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct ConsoleSessionSnapshotTests {
        @Test(
            "An earlier session under Previous: Captured and Previous, the session menu, the app, the count, a torn line, and both deletes",
            arguments: [ColorScheme.light, .dark]
        )
        func previousSession(colorScheme: ColorScheme) throws {
            let started = Date(timeIntervalSince1970: 1_800_000_000)
            let encoder = JSONEncoder()
            let header = ConsoleSessionHeader(started: "2027-01-15T08:00:00.000Z", app: "Shop", appVersion: "2.1 (40)")
            let line = LogLine(timestamp: started.addingTimeInterval(1), text: "Checkout failed", source: .oslog, level: .error)
            let rows = try [encoder.encode(header), encoder.encode(ConsoleSessionLine(line)), Data(#"{"lev"#.utf8)]
            let data = Data(rows.joined(separator: Data("\n".utf8)))
            let newest = try #require(ConsoleSessionSummary(ConsoleSessionFile(
                name: "2027-01-15T080000.000Z-6E1D3C5A-2B4F-4F7E-9A51-3C1D2E4F5A6B.jsonl", byteCount: 48_000
            )))
            let older = try #require(ConsoleSessionSummary(ConsoleSessionFile(
                name: "2027-01-15T070000.000Z-9A3C5E71-4B2D-4F86-A1E9-6D7B8C0F2A35.jsonl", byteCount: 2_000
            )))
            let sut = VStack(alignment: .leading, spacing: 0) {
                ConsoleLogSourcePicker(source: .constant(.previous))
                ConsolePreviousSessionPicker(
                    sessions: [newest, older], shown: ConsoleSessionLog(summary: newest, data: data), select: { _ in }, deleteAll: {}
                )
                ConsoleToolbarView(
                    isFollowing: .constant(true), filterLevel: .constant(.debug),
                    clear: {}, source: .previous
                )
            }
            let host = NSHostingView(rootView: sut
                .environment(\.locale, Locale(identifier: "en_US"))
                .environment(\.timeZone, .gmt)
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

        @Test("Under an earlier session's page: how many older lines it leaves out, with Show Earlier", arguments: [ColorScheme.light, .dark])
        func earlierLines(colorScheme: ColorScheme) throws {
            let host = NSHostingView(rootView: ConsoleEarlierLinesHint(count: 95433) {}
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
