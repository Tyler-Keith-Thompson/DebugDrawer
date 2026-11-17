// Views render on the Mac; the snapshot packages are linked on Apple platforms only.
#if os(macOS)
    import AppKit
    import DebugDrawer
    @testable import DebugDrawerNetworkPlugin
    import SnapshotTesting
    import SwiftUI
    import Testing

    // At 316 points, the width of the drawer on an iPad and the narrowest it gets. The views hold
    // text fields, menus and disclosure groups, which ImageRenderer draws as placeholders, so they
    // are hosted in a window that is never shown and drawn into a bitmap at a fixed 2x scale, in
    // the appearance the test asks for. macOS doesn't scale text with Dynamic Type, so the Mac pins
    // light and dark only.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct NetworkIgnoreSnapshotTests {
        @Test(
            "A GraphQL request's row and detail: the path with GetUser, Operation, and Ignore Host among the actions",
            arguments: [ColorScheme.light, .dark]
        )
        func graphQLRequest(colorScheme: ColorScheme) throws {
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000), method: "POST", url: "https://api.example.com/graphql",
                host: "api.example.com", path: "/graphql", requestHeaders: [:],
                requestBody: Data(#"{"operationName":"GetUser","variables":{"id":"1"}}"#.utf8), statusCode: 200, duration: 0.142,
                isComplete: true
            )
            let other = NetworkEntry(
                timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000), method: "POST", url: "https://api.example.com/graphql",
                host: "api.example.com", path: "/graphql", requestHeaders: [:],
                requestBody: Data(#"{"query":"mutation UpdateUserPreferences { a }"}"#.utf8), statusCode: 200, duration: 0.088,
                isComplete: true
            )
            let sut = VStack(alignment: .leading, spacing: 0) {
                NetworkRequestRow(entry: other, redaction: .standard, isSelected: false, onSelect: {})
                NetworkRequestRow(
                    entry: entry, redaction: .standard, isSelected: true, onSelect: {}, onMock: { _ in }, onResend: { _ in },
                    onEditAndResend: { _ in }, onIgnore: { _ in }
                )
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

        @Test(
            "Under the log, the hint: how many the list hides with Show, and while shown, how many with Hide",
            arguments: [ColorScheme.light, .dark]
        )
        func hint(colorScheme: ColorScheme) throws {
            let sut = VStack(alignment: .leading, spacing: 0) {
                NetworkIgnoredHint(count: 12, isShowing: false) {}
                NetworkIgnoredHint(count: 12, isShowing: true) {}
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

        @Test(
            "The Ignored hosts section: each domain with Remove, the note, then the field and Ignore Host",
            arguments: [ColorScheme.light, .dark]
        )
        func section(colorScheme: ColorScheme) throws {
            let domains = try ["analytics.example.net", "cdn.example.com", "10.0.0.1"].map { try NetworkIgnoredDomain(parsing: $0) }
            let sut = NetworkIgnoreListSection(domains: domains, issue: nil, add: { _ in }, remove: { _ in })

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

        @Test(
            "A typed host that isn't one: the field keeps the text and the problem shows under it",
            arguments: [ColorScheme.light, .dark]
        )
        func invalidInput(colorScheme: ColorScheme) throws {
            let sut = NetworkIgnoreListSection(
                domains: [], issue: nil, add: { _ in }, remove: { _ in }, text: "*.example.com", problem: .wildcard
            )

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
    }
#endif
