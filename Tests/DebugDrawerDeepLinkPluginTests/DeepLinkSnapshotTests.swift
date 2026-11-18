// Views render on the Mac; the snapshot packages are linked on Apple platforms only.
#if os(macOS)
    import AppKit
    @testable import DebugDrawerDeepLinkPlugin
    import Foundation
    import SnapshotTesting
    import SwiftUI
    import Testing

    // At 316 points, the width of the drawer on an iPad and the narrowest it gets. The form holds
    // text fields and pickers, which ImageRenderer draws as placeholders, so it is hosted in a
    // window that is never shown and drawn into a bitmap at a fixed 2x scale, in the appearance
    // the test asks for: the snapshot doesn't depend on the Mac's own appearance or display. macOS
    // doesn't scale text with Dynamic Type, so the Mac pins light and dark only.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct DeepLinkSnapshotTests {
        // The share of pixels a hosted text-field snapshot must match: the AppKit field's host
        // sometimes measures it 2 pt short (DD-182), which moves only the field's text.
        private static let textFieldPrecision: Float = 0.99

        @Test(
            "With no URL typed and no history, the form shows the mode picker, the field, a disabled Open and the presets",
            arguments: [ColorScheme.light, .dark]
        )
        func empty(colorScheme: ColorScheme) throws {
            let presets: [DeepLinkPreset] = [
                try DeepLinkPreset("HTTPS", url: #require(URL(string: "https://example.com/path"))),
                try DeepLinkPreset("Custom Scheme", url: #require(URL(string: "myapp://deeplink/screen"))),
                try DeepLinkPreset("Mail", url: #require(URL(string: "mailto:test@example.com")))
            ]
            let sut = DeepLinkForm(urlText: .constant(""), presets: presets, onOpen: { _ in }, onContinue: { _ in }, onClear: {})

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
            "After an open, the form shows the URL with an Open link, the result and the history",
            arguments: [ColorScheme.light, .dark]
        )
        func afterOpening(colorScheme: ColorScheme) throws {
            let presets: [DeepLinkPreset] = [
                try DeepLinkPreset("HTTPS", url: #require(URL(string: "https://example.com/path"))),
                try DeepLinkPreset("Custom Scheme", url: #require(URL(string: "myapp://deeplink/screen")))
            ]
            let sut = DeepLinkForm(
                urlText: .constant("myapp://orders/42"),
                outcome: .opened("myapp://orders/42"),
                presets: presets,
                history: ["myapp://orders/42", "myapp://deeplink/screen"],
                onOpen: { _ in },
                onContinue: { _ in },
                onClear: {}
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

            // The AppKit text field's host sometimes measures it 2 pt short (DD-182), which moves its text.
            assertSnapshot(of: actual, as: .image(precision: Self.textFieldPrecision, perceptualPrecision: 0.98), named: "\(colorScheme)")
        }

        @Test(
            "After continuing an https URL, the form shows Universal Link, Continue, where it went and the activity history",
            arguments: [ColorScheme.light, .dark]
        )
        func universalLink(colorScheme: ColorScheme) throws {
            let presets: [DeepLinkPreset] = [
                try DeepLinkPreset("HTTPS", url: #require(URL(string: "https://example.com/path"))),
                try DeepLinkPreset("Custom Scheme", url: #require(URL(string: "myapp://deeplink/screen")))
            ]
            let activities = [
                DeepLinkActivity(activityType: NSUserActivityTypeBrowsingWeb, webpageURL: URL(string: "https://example.com/orders/42"), userInfo: []),
                DeepLinkActivity(
                    activityType: "com.example.app.viewOrder", webpageURL: nil,
                    userInfo: [UserInfoEntry(key: "orderID", value: .integer(7)), UserInfoEntry(key: "gift", value: .bool(true))]
                )
            ]
            let sut = DeepLinkForm(
                urlText: .constant("https://example.com/orders/42"),
                outcome: .continued(.handler),
                presets: presets,
                history: ["myapp://orders/42"],
                activities: activities,
                onOpen: { _ in },
                onContinue: { _ in },
                onClear: {}
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

            // The AppKit text field's host sometimes measures it 2 pt short (DD-182), which moves its text.
            assertSnapshot(of: actual, as: .image(precision: Self.textFieldPrecision, perceptualPrecision: 0.98), named: "\(colorScheme)")
        }

        @Test(
            "In Activity mode with no handler, the form shows the type, a row of each userInfo type, Add Key and what to do",
            arguments: [ColorScheme.light, .dark]
        )
        func activity(colorScheme: ColorScheme) throws {
            let draft = ActivityDraft(activityType: "com.example.app.viewOrder", fields: [
                UserInfoField(key: "orderID", kind: .number, text: "42"),
                UserInfoField(key: "title", kind: .string, text: "Ada's order"),
                UserInfoField(key: "gift", kind: .boolean, isOn: true)
            ])
            let sut = DeepLinkForm(
                urlText: .constant(""),
                outcome: .continued(.unhandled),
                presets: [],
                mode: .activity,
                draft: draft,
                onOpen: { _ in },
                onContinue: { _ in },
                onClear: {}
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

            // The AppKit text field's host sometimes measures it 2 pt short (DD-182), which moves its text.
            assertSnapshot(of: actual, as: .image(precision: Self.textFieldPrecision, perceptualPrecision: 0.98), named: "\(colorScheme)")
        }
    }
#endif
