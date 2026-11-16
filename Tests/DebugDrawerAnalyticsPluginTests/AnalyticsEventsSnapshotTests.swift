// Views render on the Mac; the snapshot packages are linked on Apple platforms only.
#if os(macOS)
    import AppKit
    @testable import DebugDrawerAnalyticsPlugin
    import SnapshotTesting
    import SwiftUI
    import Testing

    // ImageRenderer draws AppKit-backed controls (the filter field, the buttons) as placeholders,
    // so the tests host the view in a window that is never shown and draw it into a bitmap at a
    // fixed 2x scale, in the appearance the test asks for: the snapshot doesn't depend on the Mac's
    // own appearance or display. macOS doesn't scale text with Dynamic Type, so the Mac pins light
    // and dark only. Times are drawn in en_US and UTC, so the snapshot doesn't depend on the Mac's
    // settings.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct AnalyticsEventsSnapshotTests {
        @Test("Events list the newest first, each with its name cut in the middle, its time, source and property count, then Export All and Clear",
              arguments: [ColorScheme.light, .dark])
        func events(colorScheme: ColorScheme) throws {
            let opened = AnalyticsEvent(
                id: 3, timestamp: Date(timeIntervalSince1970: 1_763_290_000.25), name: "checkout_completed",
                properties: [
                    "plan": "pro", "seats": 3, "total": 29.99, "trial": false, "coupon": nil,
                    "items": ["sku-1", "sku-2"], "auth_token": "t0k3n"
                ],
                source: "Segment"
            )
            let others = [
                AnalyticsEvent(
                    id: 2, timestamp: Date(timeIntervalSince1970: 1_763_289_998.5),
                    name: "onboarding_paywall_viewed_after_trial_reminder_notification",
                    properties: ["variant": "b"], source: "Segment"
                ),
                AnalyticsEvent(id: 1, timestamp: Date(timeIntervalSince1970: 1_763_289_990), name: "app_opened", properties: [:], source: nil)
            ]
            let sut = AnalyticsEventsView(
                events: [opened] + others, capacity: 1000, query: .constant(""), selected: .constant(nil),
                redaction: .standard, onClear: {}
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

        @Test("The selected event is drawn selected; below the list, its name, properties (one masked), whole JSON and Copy JSON",
              arguments: [ColorScheme.light, .dark])
        func selectedEvent(colorScheme: ColorScheme) throws {
            let opened = AnalyticsEvent(
                id: 3, timestamp: Date(timeIntervalSince1970: 1_763_290_000.25), name: "checkout_completed",
                properties: [
                    "plan": "pro", "seats": 3, "total": 29.99, "trial": false, "coupon": nil,
                    "items": ["sku-1", "sku-2"], "auth_token": "t0k3n"
                ],
                source: "Segment"
            )
            let others = [
                AnalyticsEvent(
                    id: 2, timestamp: Date(timeIntervalSince1970: 1_763_289_998.5),
                    name: "onboarding_paywall_viewed_after_trial_reminder_notification",
                    properties: ["variant": "b"], source: "Segment"
                ),
                AnalyticsEvent(id: 1, timestamp: Date(timeIntervalSince1970: 1_763_289_990), name: "app_opened", properties: [:], source: nil)
            ]
            let sut = AnalyticsEventsView(
                events: [opened] + others, capacity: 1000, query: .constant(""), selected: .constant(opened.id),
                redaction: .standard, onClear: {}
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

        @Test("A filter that matches nothing says so", arguments: [ColorScheme.light, .dark])
        func noMatch(colorScheme: ColorScheme) throws {
            let event = AnalyticsEvent(id: 1, timestamp: Date(timeIntervalSince1970: 1_763_289_990), name: "app_opened", properties: [:], source: nil)
            let sut = AnalyticsEventsView(
                events: [event], capacity: 1000, query: .constant("refund"), selected: .constant(nil), redaction: .standard, onClear: {}
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

        @Test("With no events the plugin says how they arrive", arguments: [ColorScheme.light, .dark])
        func empty(colorScheme: ColorScheme) throws {
            let sut = AnalyticsEventsView(
                events: [], capacity: 1000, query: .constant(""), selected: .constant(nil), redaction: .standard, onClear: {}
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
