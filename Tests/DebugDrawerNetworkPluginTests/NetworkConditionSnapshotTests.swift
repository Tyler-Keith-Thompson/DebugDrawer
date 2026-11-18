// Views render on the Mac; the snapshot packages are linked on Apple platforms only.
#if os(macOS)
    import AppKit
    @testable import DebugDrawerNetworkPlugin
    import SnapshotTesting
    import SwiftUI
    import Testing

    // ImageRenderer draws AppKit-backed controls (the switches, pickers and text fields) as
    // placeholders, so the Conditions section and the editor are hosted in a window that is never
    // shown and drawn into a bitmap at a fixed 2x scale, in the appearance the test asks for. macOS
    // doesn't scale text with Dynamic Type, so the Mac pins light and dark only.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct NetworkConditionSnapshotTests {
        // The share of pixels a hosted text-field snapshot must match: the AppKit field's host sometimes
        // measures it 2 pt short (DD-182), which moves only the field's text.
        private static let textFieldPrecision: Float = 0.99

        @Test(
            "The Conditions section: each profile's switch, name, effect and hosts, the selected one's actions, then Add Condition",
            arguments: [ColorScheme.light, .dark]
        )
        func conditionsSection(colorScheme: ColorScheme) throws {
            let threeG = NetworkConditionProfile(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID(),
                name: "3G", host: .exact("api.example.com"), latency: .milliseconds(100), bandwidth: 97500
            )
            let offline = NetworkConditionProfile(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000002") ?? UUID(),
                name: "Payments offline", host: .wildcard("*.payments.example.com"), failureRate: 100, failure: .notConnectedToInternet
            )
            let lossy = NetworkConditionProfile(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000003") ?? UUID(),
                name: "Lossy", isEnabled: false, latency: .milliseconds(500), bandwidth: 125_000, failureRate: 10, failure: .timedOut
            )
            let sut = NetworkConditionsSection(
                profiles: [threeG, offline, lossy], issue: nil, selected: .constant(offline.id),
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
            "The editor: name and switch, the host's match and pattern, a preset, latency, bandwidth, failure rate and failure",
            arguments: [ColorScheme.light, .dark]
        )
        func conditionEditor(colorScheme: ColorScheme) throws {
            let profile = NetworkConditionProfile(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID(),
                name: "Slow API", host: .exact("api.example.com"), latency: .milliseconds(2000), bandwidth: 50000, failureRate: 10,
                failure: .internalServerError
            )
            let sut = NetworkConditionEditor(draft: NetworkConditionDraft(profile, isNew: false), cancel: {}, save: { _ in })
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

        @Test(
            "A conditioned, mocked request shows Mocked and Conditioned on a line below its status and, selected, the profile and what it did",
            arguments: [ColorScheme.light, .dark]
        )
        func conditionedRow(colorScheme: ColorScheme) throws {
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000), method: "GET",
                url: "https://api.example.com/v1/greeting", host: "api.example.com", path: "/v1/greeting",
                requestHeaders: [:], requestBody: nil, statusCode: 200,
                responseHeaders: ["Content-Type": "application/json", "Content-Length": "31"],
                responseBody: Data(#"{"message":"Hello from a mock"}"#.utf8), duration: 2.004, isComplete: true,
                mockRuleName: "Greeting",
                conditionEffect: NetworkConditionEffect(profileName: "Slow API", latency: .milliseconds(2000), bandwidth: 50000, failure: nil)
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

        @Test("The header with a profile on: the failures, the indicator and the request count", arguments: [ColorScheme.light, .dark])
        func headerIndicator(colorScheme: ColorScheme) throws {
            let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
            let entries = [
                NetworkEntry(timestamp: start, method: "GET", url: "", host: "", path: "", requestHeaders: [:], requestBody: nil,
                             statusCode: 200, isComplete: true),
                NetworkEntry(timestamp: start, method: "GET", url: "", host: "", path: "", requestHeaders: [:], requestBody: nil,
                             error: "Timed out", isComplete: true)
            ]
            let sut = NetworkHeaderSummary(entries: entries, activeMocks: 1, conditions: [NetworkConditionProfile(name: "3G")])
            let renderer = ImageRenderer(content: sut
                .debugDrawerFont(.code)
                .debugDrawerForegroundStyle(.tertiary)
                .padding()
                .background(.background)
                .environment(\.colorScheme, colorScheme))
            renderer.scale = 2

            let actual = try #require(renderer.nsImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
        }

        @Test("The HUD readout while a profile is on, and while none is", arguments: [ColorScheme.light, .dark])
        func hudReadout(colorScheme: ColorScheme) throws {
            let sut = VStack(alignment: .leading, spacing: 6) {
                NetworkConditionsHUDReadout(summary: "Slow API active")
                NetworkConditionsHUDReadout(summary: nil)
            }
            let renderer = ImageRenderer(content: sut
                .padding(8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .padding()
                .background(.background)
                .environment(\.colorScheme, colorScheme))
            renderer.scale = 2

            let actual = try #require(renderer.nsImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
        }
    }
#endif
