// Views render on the Mac; the snapshot packages are linked on Apple platforms only.
#if os(macOS)
    import AppKit
    @testable import DebugDrawerNetworkPlugin
    import SnapshotTesting
    import SwiftUI
    import Testing

    // ImageRenderer draws AppKit-backed controls (the switches, pickers and text fields) as
    // placeholders, so the Mocks section and the editor are hosted in a window that is never shown
    // and drawn into a bitmap at a fixed 2x scale, in the appearance the test asks for. macOS
    // doesn't scale text with Dynamic Type, so the Mac pins light and dark only.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct NetworkMockSnapshotTests {
        // The share of pixels a hosted text-field snapshot must match: the AppKit field's host sometimes
        // measures it 2 pt short (DD-182), which moves only the field's text.
        private static let textFieldPrecision: Float = 0.99

        @Test(
            "The Mocks section: each rule's switch, name, status, methods and pattern, the selected one's actions, then Add Mock",
            arguments: [ColorScheme.light, .dark]
        )
        func mocksSection(colorScheme: ColorScheme) throws {
            let greeting = NetworkMockRule(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID(),
                name: "Greeting", matcher: .init(methods: ["GET"], host: .exact("api.example.com"), path: .wildcard("/v1/greeting/*")),
                response: .init(status: 200)
            )
            let outage = NetworkMockRule(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000002") ?? UUID(),
                name: "Orders outage", matcher: .init(methods: ["GET", "POST"], host: .wildcard("*.example.com"), path: .wildcard("/v1/orders/**")),
                response: .init(status: 503)
            )
            let legacy = NetworkMockRule(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000003") ?? UUID(),
                name: "Legacy users", isEnabled: false, matcher: .init(methods: ["PUT"], path: .regex(#"/v0/users/\d+"#)),
                response: .init(status: 404)
            )
            let sut = NetworkMocksSection(
                rules: [greeting, outage, legacy], issue: nil, selected: .constant(outage.id),
                setEnabled: { _, _ in }, add: {}, edit: { _ in }, move: { _, _ in }, delete: { _ in }
            )
            let host = NSHostingView(rootView: sut
                .environment(\.locale, Locale(identifier: "en_US"))
                .frame(width: 360, alignment: .leading)
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
            "The editor: name and switch, methods, host and path patterns, query, status, content type, headers and a text body",
            arguments: [ColorScheme.light, .dark]
        )
        func editor(colorScheme: ColorScheme) throws {
            let rule = NetworkMockRule(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID(),
                name: "Greeting",
                matcher: .init(methods: ["GET"], host: .exact("api.example.com"), path: .wildcard("/v1/greeting/*"), query: ["lang": "en"]),
                response: .init(
                    status: 200, headers: ["Cache-Control": "no-store"], body: .text(#"{"message":"Hello from a mock"}"#),
                    contentType: "application/json"
                )
            )
            let sut = NetworkMockEditor(draft: NetworkMockDraft(rule, isNew: false), importBody: { _ in nil }, cancel: {}, save: { _ in })
            let host = NSHostingView(rootView: sut
                .environment(\.locale, Locale(identifier: "en_US"))
                .frame(width: 360, alignment: .leading)
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

            // The AppKit text field's host sometimes measures it 2 pt short (DD-182), which moves its text.
            assertSnapshot(of: actual, as: .image(precision: Self.textFieldPrecision, perceptualPrecision: 0.98), named: "\(colorScheme)")
        }

        @Test("An invalid regex says why below its field, and Save is unavailable", arguments: [ColorScheme.light, .dark])
        func editorInvalidRegex(colorScheme: ColorScheme) throws {
            var draft = NetworkMockDraft.new()
            draft.hostKind = .exact
            draft.host = "api.example.com"
            draft.pathKind = .regex
            draft.path = #"/users/(\d+"#
            let sut = NetworkMockEditor(draft: draft, importBody: { _ in nil }, cancel: {}, save: { _ in })
            let host = NSHostingView(rootView: sut
                .environment(\.locale, Locale(identifier: "en_US"))
                .frame(width: 360, alignment: .leading)
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

            // The AppKit text field's host sometimes measures it 2 pt short (DD-182), which moves its text.
            assertSnapshot(of: actual, as: .image(precision: Self.textFieldPrecision, perceptualPrecision: 0.98), named: "\(colorScheme)")
        }

        @Test("A mocked request shows Mocked beside its status and, selected, the rule that answered", arguments: [ColorScheme.light, .dark])
        func mockedRow(colorScheme: ColorScheme) throws {
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000), method: "GET",
                url: "https://api.example.com/v1/greeting/ada", host: "api.example.com", path: "/v1/greeting/ada",
                requestHeaders: [:], requestBody: nil, statusCode: 200,
                responseHeaders: ["Content-Type": "application/json", "Content-Length": "31"],
                responseBody: Data(#"{"message":"Hello from a mock"}"#.utf8), duration: 0.0004, isComplete: true,
                mockRuleName: "Greeting"
            )
            let sut = NetworkRequestRow(entry: entry, redaction: .standard, isSelected: true, onSelect: {}, onMock: { _ in })
            let renderer = ImageRenderer(content: sut
                .frame(width: 320, alignment: .leading)
                .padding()
                .background(.background)
                .environment(\.colorScheme, colorScheme))
            renderer.scale = 2

            let actual = try #require(renderer.nsImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
        }
    }
#endif
