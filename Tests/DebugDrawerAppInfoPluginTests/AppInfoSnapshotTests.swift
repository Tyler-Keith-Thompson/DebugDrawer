// Views render on the Mac; the snapshot packages are linked on Apple platforms only.
#if os(macOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    @testable import DebugDrawerAppInfoPlugin

    // ImageRenderer draws the view without a window, at a fixed scale, in the color scheme the
    // test asks for, so a snapshot doesn't depend on the Mac's own appearance or display. macOS
    // doesn't scale text with Dynamic Type, so the Mac pins light and dark only.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct AppInfoSnapshotTests {
        @Test("The facts view shows each section's facts, then the copy and refresh buttons", arguments: [ColorScheme.light, .dark])
        func factsView(colorScheme: ColorScheme) throws {
            let facts = AppInfoFacts(sections: [
                [
                    .init(label: "Bundle ID", value: "com.example.App"),
                    .init(label: "Version", value: "1.2.3 (45)")
                ],
                [
                    .init(label: "Memory", value: "182.4 MB"),
                    .init(label: "Uptime", value: "2m 14s")
                ],
                [
                    .init(label: "OS", value: "macOS 15.4"),
                    .init(label: "Device", value: "arm64")
                ]
            ])
            let sut = AppInfoFactsView(facts: facts) {}
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
