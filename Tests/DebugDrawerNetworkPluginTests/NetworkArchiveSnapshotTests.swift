// Views render on the Mac; the snapshot packages are linked on Apple platforms only.
#if os(macOS)
    import AppKit
    import DebugDrawer
    @testable import DebugDrawerNetworkPlugin
    import SnapshotTesting
    import SwiftUI
    import Testing

    // At 316 points, the width of the drawer on an iPad and the narrowest it gets. The controls
    // hold segmented pickers, which ImageRenderer draws as placeholders, so they are hosted in a
    // window that is never shown and drawn into a bitmap at a fixed 2x scale, in the appearance the
    // test asks for. The request row draws SwiftUI's own views, so ImageRenderer draws it. macOS
    // doesn't scale text with Dynamic Type, so the Mac pins light and dark only.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct NetworkArchiveSnapshotTests {
        @Test(
            "An imported file: Captured and Imported, the file and its count, the filter, Export Shown, Import HAR… and Clear, a refused file",
            arguments: [ColorScheme.light, .dark]
        )
        func controls(colorScheme: ColorScheme) throws {
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000), method: "GET", url: "https://shop.example.com/api/cart",
                host: "shop.example.com", path: "/api/cart", requestHeaders: [:], requestBody: nil, statusCode: 500, isComplete: true
            )
            let issue = NetworkImportIssue(fileName: "notes.json", error: .notAnArchive)
            let sut = VStack(alignment: .leading, spacing: 0) {
                NetworkLogSourcePicker(source: .constant(.imported), fileName: "shop.example.com.har", count: 12)
                NetworkToolbar(
                    filterStatus: .constant(.serverError), clear: {}, export: NetworkArchiveFile(entries: [entry], redaction: .standard),
                    isFiltered: true, importArchive: {}, source: .imported
                )
                DebugDrawerIssueRow("Not imported", severity: .error) {
                    Text(issue.message)
                }
            }
            let host = NSHostingView(rootView: sut
                .environment(\.locale, Locale(identifier: "en_US"))
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

        @Test("An imported request's detail offers no Resend, only More", arguments: [ColorScheme.light, .dark])
        func importedRow(colorScheme: ColorScheme) throws {
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000), method: "GET", url: "https://shop.example.com/api/cart?id=12",
                host: "shop.example.com", path: "/api/cart", requestHeaders: ["Authorization": "[REDACTED]", "accept": "application/json"],
                requestBody: nil, statusCode: 200, responseHeaders: ["content-type": "application/json"],
                responseBody: Data(#"{"items":2}"#.utf8), duration: 0.048, isComplete: true
            )
            let sut = NetworkRequestRow(entry: entry, redaction: .standard, isSelected: true, onSelect: {}, onMock: { _ in }, onShow: { _ in })
            let renderer = ImageRenderer(content: sut
                .environment(\.locale, Locale(identifier: "en_US"))
                .frame(width: 316, alignment: .leading)
                .padding()
                .background(.background)
                .environment(\.colorScheme, colorScheme))
            renderer.scale = 2

            let actual = try #require(renderer.nsImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
        }
    }
#endif
