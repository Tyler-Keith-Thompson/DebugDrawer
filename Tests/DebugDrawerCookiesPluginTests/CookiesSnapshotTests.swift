// Views render on the Mac; the snapshot packages are linked on Apple platforms only.
#if os(macOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    @testable import DebugDrawerCookiesPlugin

    // ImageRenderer draws the view without a window, at a fixed scale, in the color scheme the
    // test asks for, so a snapshot doesn't depend on the Mac's own appearance or display. macOS
    // doesn't scale text with Dynamic Type, so the Mac pins light and dark only.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct CookiesSnapshotTests {
        @Test("A collapsed cookie row shows the name, the domain and a delete button", arguments: [ColorScheme.light, .dark])
        func collapsedRow(colorScheme: ColorScheme) throws {
            let cookie = try #require(HTTPCookie(properties: [
                .name: "session", .value: "a1b2c3", .domain: "example.com", .path: "/"
            ]))
            let sut = CookieRow(cookie: cookie) {}
            let renderer = ImageRenderer(content: sut
                .frame(width: 320, alignment: .leading)
                .padding()
                .background(.background)
                .environment(\.colorScheme, colorScheme))
            renderer.scale = 2

            let actual = try #require(renderer.nsImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
        }

        @Test("A cookie's details list the value, domain, path, flags and expiry", arguments: [ColorScheme.light, .dark])
        func details(colorScheme: ColorScheme) throws {
            let cookie = try #require(HTTPCookie(properties: [
                .name: "session", .value: "a1b2c3", .domain: "example.com", .path: "/", .secure: "TRUE"
            ]))
            let sut = CookieDetails(cookie: cookie)
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
