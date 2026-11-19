// Views render on the Mac; the snapshot packages are linked on Apple platforms only.
#if os(macOS)
    import AppKit
    import DebugDrawer
    import SnapshotTesting
    import SwiftUI
    import Testing
    @testable import DebugDrawerCookiesPlugin

    // The plugin's whole view, drawn from a transport that holds a fixed snapshot and drops every
    // command, so nothing reads a cookie store. ImageRenderer draws the filter's AppKit-backed text
    // field as a placeholder, so the view is hosted in a window that is never shown and drawn into
    // a bitmap at a fixed 2x scale, in the appearance the test asks for. macOS doesn't scale text
    // with Dynamic Type, so the Mac pins light and dark only.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct CookiesPluginViewSnapshotTests {
        @Test("The plugin lists both stores' cookies under the count, the buttons and the filter", arguments: [ColorScheme.light, .dark])
        func cookies(colorScheme: ColorScheme) throws {
            let snapshot = CookiesSnapshot(contents: .cookies([
                StoredCookie(
                    name: "session", value: "a1b2c3", domain: "api.example.com", path: "/", store: .urlSession,
                    isSecure: true, isHTTPOnly: true, expiresDate: nil
                ),
                StoredCookie(
                    name: "csrftoken", value: "x9y8z7", domain: ".web.example.com", path: "/", store: .webView,
                    isSecure: true, isHTTPOnly: false, expiresDate: nil
                ),
                StoredCookie(
                    name: "theme", value: "dark", domain: ".web.example.com", path: "/", store: .webView,
                    isSecure: false, isHTTPOnly: false, expiresDate: nil
                )
            ]), filter: "")
            let sut = CookiesPluginView(transport: DebugDrawerPluginTransport(
                initial: snapshot, snapshots: AsyncStream { $0.finish() }, send: { _ in }
            ))
            let host = NSHostingView(rootView: sut
                .frame(width: 316, alignment: .leading)
                // No height proposed, as the drawer's scroll view proposes none.
                .fixedSize(horizontal: false, vertical: true)
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

        @Test("A filter that matches none of the cookies says No matches under the count of all", arguments: [ColorScheme.light, .dark])
        func noMatches(colorScheme: ColorScheme) throws {
            let snapshot = CookiesSnapshot(contents: .cookies([
                StoredCookie(
                    name: "session", value: "a1b2c3", domain: "api.example.com", path: "/", store: .urlSession,
                    isSecure: true, isHTTPOnly: true, expiresDate: nil
                ),
                StoredCookie(
                    name: "theme", value: "dark", domain: ".web.example.com", path: "/", store: .webView,
                    isSecure: false, isHTTPOnly: false, expiresDate: nil
                )
            ]), filter: "analytics")
            let sut = CookiesPluginView(transport: DebugDrawerPluginTransport(
                initial: snapshot, snapshots: AsyncStream { $0.finish() }, send: { _ in }
            ))
            let host = NSHostingView(rootView: sut
                .frame(width: 316, alignment: .leading)
                // No height proposed, as the drawer's scroll view proposes none.
                .fixedSize(horizontal: false, vertical: true)
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
