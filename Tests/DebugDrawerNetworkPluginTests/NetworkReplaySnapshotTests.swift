// Views render on the Mac; the snapshot packages are linked on Apple platforms only.
#if os(macOS)
    import AppKit
    @testable import DebugDrawerNetworkPlugin
    import SnapshotTesting
    import SwiftUI
    import Testing

    // The request rows draw SwiftUI's own views, so ImageRenderer draws them, at 316 points, the
    // width of the drawer on an iPad and the narrowest it gets, so the detail's actions are seen
    // wrapping there. The editor has AppKit-backed text fields and menus, which ImageRenderer draws
    // as placeholders, so it is hosted in a window that is never shown and drawn into a bitmap at
    // a fixed 2x scale, in the appearance the test asks for. macOS doesn't scale text with Dynamic
    // Type, so the Mac pins light and dark only.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct NetworkReplaySnapshotTests {
        // The share of pixels a hosted text-field snapshot must match: the AppKit field's host sometimes
        // measures it 2 pt short (DD-182), which moves only the field's text.
        private static let textFieldPrecision: Float = 0.99

        @Test(
            "A mocked replay shows Replay and Mocked beside its status, its path below, and its detail links to the original, above the actions",
            arguments: [ColorScheme.light, .dark]
        )
        func replayRow(colorScheme: ColorScheme) throws {
            let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
            let original = NetworkEntry(
                timestamp: start, method: "GET", url: "https://api.example.com/v1/greeting/ada", host: "api.example.com",
                path: "/v1/greeting/ada", requestHeaders: [:], requestBody: nil, statusCode: 200, duration: 0.12, isComplete: true
            )
            let replay = NetworkEntry(
                timestamp: start + 42, method: "GET", url: original.url, host: original.host, path: original.path,
                requestHeaders: ["Accept": "application/json"], requestBody: nil, statusCode: 200,
                responseHeaders: ["Content-Type": "application/json"], responseBody: Data(#"{"message":"Hello"}"#.utf8),
                duration: 0.0004, isComplete: true, mockRuleName: "Greeting", replayOf: original.id
            )
            let sut = NetworkRequestRow(
                entry: replay, redaction: .standard, isSelected: true, onSelect: {}, onMock: { _ in }, onResend: { _ in },
                onEditAndResend: { _ in }, onShow: { _ in }, links: NetworkReplayLinks(of: replay, in: [replay, original])
            )
            let renderer = ImageRenderer(content: sut
                .environment(\.locale, Locale(identifier: "en_US"))
                .environment(\.timeZone, TimeZone(identifier: "UTC") ?? .gmt)
                .frame(width: 316, alignment: .leading)
                .padding()
                .background(.background)
                .environment(\.colorScheme, colorScheme))
            renderer.scale = 2

            let actual = try #require(renderer.nsImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
        }

        @Test(
            "Resending a POST asks in place under the actions, with Send and Cancel; the detail says it was resent twice",
            arguments: [ColorScheme.light, .dark]
        )
        func confirmation(colorScheme: ColorScheme) throws {
            let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
            let original = NetworkEntry(
                timestamp: start, method: "POST", url: "https://api.example.com/v1/orders", host: "api.example.com",
                path: "/v1/orders", requestHeaders: ["Content-Type": "application/json"], requestBody: Data(#"{"item":"tea"}"#.utf8),
                statusCode: 201, duration: 0.18, isComplete: true
            )
            let replays = [2, 1].map { offset in
                NetworkEntry(
                    timestamp: start + Double(offset), method: "POST", url: original.url, host: original.host, path: original.path,
                    requestHeaders: [:], requestBody: nil, statusCode: 201, isComplete: true, replayOf: original.id
                )
            }
            let sut = NetworkRequestDetail(
                entry: original, redaction: .standard, onMock: { _ in }, onResend: { _ in }, onEditAndResend: { _ in }, onShow: { _ in },
                links: NetworkReplayLinks(of: original, in: replays + [original]), isConfirming: true
            )
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

        @Test("A resend that got no answer says why, under the actions", arguments: [ColorScheme.light, .dark])
        func failedResend(colorScheme: ColorScheme) throws {
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000), method: "GET", url: "https://api.example.com/v1/greeting",
                host: "api.example.com", path: "/v1/greeting", requestHeaders: [:], requestBody: nil, statusCode: 200, duration: 0.12,
                isComplete: true
            )
            let sut = NetworkRequestDetail(
                entry: entry, redaction: .standard, onMock: { _ in }, onResend: { _ in }, onEditAndResend: { _ in },
                replayStatus: .failed("The Internet connection appears to be offline.")
            )
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

        @Test("Edit and Resend: the method, the URL, each header and the body, then Send and Cancel", arguments: [ColorScheme.light, .dark])
        func replayEditor(colorScheme: ColorScheme) throws {
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000), method: "POST", url: "https://api.example.com/v1/orders",
                host: "api.example.com", path: "/v1/orders", requestHeaders: ["Content-Type": "application/json", "X-Client": "app"],
                requestBody: Data(#"{"item":"tea","quantity":1}"#.utf8), statusCode: 201, isComplete: true
            )
            let sut = NetworkReplayEditor(draft: NetworkReplayDraft(entry), cancel: {}, send: { _ in })
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

            // The AppKit text field's host sometimes measures it 2 pt short (DD-182), which moves its text.
            assertSnapshot(of: actual, as: .image(precision: Self.textFieldPrecision, perceptualPrecision: 0.98), named: "\(colorScheme)")
        }

        @Test(
            "A request whose body the log cut short has Resend unavailable, and says why under the actions",
            arguments: [ColorScheme.light, .dark]
        )
        func resendUnavailable(colorScheme: ColorScheme) throws {
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000), method: "POST", url: "https://api.example.com/v1/upload",
                host: "api.example.com", path: "/v1/upload", requestHeaders: [:], requestBody: Data(repeating: 0x61, count: 1024),
                requestBodySize: 4096, statusCode: 201, duration: 0.18, isComplete: true
            )
            let sut = NetworkRequestDetail(entry: entry, redaction: .standard, onMock: { _ in }, onResend: { _ in }, onEditAndResend: { _ in })
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

        @Test(
            "Edit and Resend of a body the log cut short says how much was kept of how much, offers Edit Kept Part and Remove Body, and Send waits",
            arguments: [ColorScheme.light, .dark]
        )
        func editorTruncatedBody(colorScheme: ColorScheme) throws {
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000), method: "POST", url: "https://api.example.com/v1/upload",
                host: "api.example.com", path: "/v1/upload", requestHeaders: ["Content-Type": "application/json"],
                requestBody: Data(String(repeating: "a", count: 1024).utf8), requestBodySize: 4096, statusCode: 201, isComplete: true
            )
            let sut = NetworkReplayEditor(draft: NetworkReplayDraft(entry), cancel: {}, send: { _ in })
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

            // The AppKit text field's host sometimes measures it 2 pt short (DD-182), which moves its text.
            assertSnapshot(of: actual, as: .image(precision: Self.textFieldPrecision, perceptualPrecision: 0.98), named: "\(colorScheme)")
        }
    }
#endif
