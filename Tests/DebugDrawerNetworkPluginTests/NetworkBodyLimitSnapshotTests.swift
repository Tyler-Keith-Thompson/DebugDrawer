// Views render on the Mac; the snapshot packages are linked on Apple platforms only.
#if os(macOS)
    @testable import DebugDrawerNetworkPlugin
    import SnapshotTesting
    import SwiftUI
    import Testing

    // At 316 points, the width of the drawer on an iPad and the narrowest it gets, so the note is
    // seen wrapping there. The detail draws SwiftUI's own views above its collapsed sections, so
    // ImageRenderer draws it. macOS doesn't scale text with Dynamic Type, so the Mac pins light and
    // dark only.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct NetworkBodyLimitSnapshotTests {
        @Test(
            "A response whose body the log cut short shows its full size, and says under it how much the log keeps",
            arguments: [ColorScheme.light, .dark]
        )
        func truncatedDetail(colorScheme: ColorScheme) throws {
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000), method: "GET",
                url: "https://cdn.example.com/v1/catalog.json", host: "cdn.example.com", path: "/v1/catalog.json",
                requestHeaders: [:], requestBody: nil, statusCode: 200, responseHeaders: ["Content-Type": "application/json"],
                responseBody: Data(repeating: UInt8(ascii: "a"), count: 1024), responseBodySize: 3_565_158, duration: 1.42,
                isComplete: true
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
    }
#endif
