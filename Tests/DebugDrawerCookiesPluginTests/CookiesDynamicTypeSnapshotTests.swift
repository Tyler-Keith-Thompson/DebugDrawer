// iOS scales text with Dynamic Type, so the large-text snapshots run on the iOS simulator.
#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    @testable import DebugDrawerCookiesPlugin

    // ImageRenderer draws the view without a window, at a fixed scale and width, so the
    // reference doesn't depend on which simulator runs it.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct CookiesDynamicTypeSnapshotTests {
        @Test("A cookie's details stay readable at a large accessibility text size")
        func details() throws {
            let cookie = try #require(HTTPCookie(properties: [
                .name: "session", .value: "a1b2c3", .domain: "example.com", .path: "/", .secure: "TRUE"
            ]))
            let sut = CookieDetails(stored: StoredCookie(cookie: cookie, store: .urlSession), redaction: .standard)
            let renderer = ImageRenderer(content: sut
                .frame(width: 320, alignment: .leading)
                .padding()
                .background(.background)
                .environment(\.dynamicTypeSize, .accessibility3))
            renderer.scale = 2

            let actual = try #require(renderer.uiImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "accessibility3")
        }

        @Test("In an iPad's drawer, a web view's cookie row keeps its name, domain and store readable at a large accessibility text size")
        func webViewRow() throws {
            let cookie = try #require(HTTPCookie(properties: [
                .name: "csrftoken", .value: "x9y8z7", .domain: ".web.example.com", .path: "/"
            ]))
            let sut = CookieRow(
                stored: StoredCookie(cookie: cookie, store: .webView), redaction: .standard, isExpanded: false, toggle: {}, onDelete: {}
            )
            let renderer = ImageRenderer(content: sut
                .frame(width: 316, alignment: .leading)
                .padding()
                .background(.background)
                .environment(\.dynamicTypeSize, .accessibility3))
            renderer.scale = 2

            let actual = try #require(renderer.uiImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "accessibility3")
        }
    }
#endif
