// iOS scales text with Dynamic Type, so the large-text snapshots run on the iOS simulator.
#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    @testable import DebugDrawerDeepLinkPlugin

    // ImageRenderer draws the view without a window, at a fixed scale and width, so the
    // reference doesn't depend on which simulator runs it.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct DeepLinkDynamicTypeSnapshotTests {
        @Test("With no URL typed and no history, the form stays readable at a large accessibility text size")
        func empty() throws {
            let presets: [DeepLinkForm.Preset] = [
                .init(label: "HTTPS", url: "https://example.com/path"),
                .init(label: "Custom Scheme", url: "myapp://deeplink/screen"),
                .init(label: "Mail", url: "mailto:test@example.com")
            ]
            let sut = DeepLinkForm(
                urlText: .constant(""), lastResult: nil, presets: presets, history: [], onOpen: { _ in }, onClear: {}
            )
            let renderer = ImageRenderer(content: sut
                .frame(width: 320, alignment: .leading)
                .padding()
                .background(.background)
                .environment(\.dynamicTypeSize, .accessibility3))
            renderer.scale = 2

            let actual = try #require(renderer.uiImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "accessibility3")
        }

        @Test("After an open, the form stays readable at a large accessibility text size")
        func afterOpening() throws {
            let presets: [DeepLinkForm.Preset] = [
                .init(label: "HTTPS", url: "https://example.com/path"),
                .init(label: "Custom Scheme", url: "myapp://deeplink/screen")
            ]
            let sut = DeepLinkForm(
                urlText: .constant("myapp://orders/42"),
                lastResult: "Opened: myapp://orders/42",
                presets: presets,
                history: ["myapp://orders/42", "https://example.com/path"],
                onOpen: { _ in },
                onClear: {}
            )
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
