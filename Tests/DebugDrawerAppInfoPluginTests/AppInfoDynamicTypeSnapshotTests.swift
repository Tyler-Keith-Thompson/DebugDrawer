// iOS scales text with Dynamic Type, so the large-text snapshots run on the iOS simulator.
#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    @testable import DebugDrawerAppInfoPlugin

    // ImageRenderer draws the view without a window, at a fixed scale and width, so the
    // reference doesn't depend on which simulator runs it.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct AppInfoDynamicTypeSnapshotTests {
        @Test("The facts view stays readable at a large accessibility text size")
        func factsView() throws {
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
                .environment(\.dynamicTypeSize, .accessibility3))
            renderer.scale = 2

            let actual = try #require(renderer.uiImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "accessibility3")
        }
    }
#endif
