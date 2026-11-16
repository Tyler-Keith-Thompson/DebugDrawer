// iOS scales text with Dynamic Type, so the large-text snapshots run on the iOS simulator.
#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    @testable import DebugDrawerKeychainPlugin

    // ImageRenderer draws the view without a window, at a fixed scale and width, so the
    // reference doesn't depend on which simulator runs it.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct KeychainDynamicTypeSnapshotTests {
        @Test("An unselected keychain row stays readable at a large accessibility text size")
        func unselectedRow() throws {
            let entry = KeychainEntry(
                itemClass: "Generic Password", account: "ada@example.com", service: "com.example.App",
                label: "API token", data: Data("s3cr3t-token".utf8)
            )
            let sut = KeychainRow(entry: entry, redaction: .standard, isSelected: false, onSelect: {}, onDelete: {})
            let renderer = ImageRenderer(content: sut
                .frame(width: 320, alignment: .leading)
                .padding()
                .background(.background)
                .environment(\.dynamicTypeSize, .accessibility3))
            renderer.scale = 2

            let actual = try #require(renderer.uiImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "accessibility3")
        }

        @Test("A selected keychain row stays readable at a large accessibility text size")
        func selectedRow() throws {
            let entry = KeychainEntry(
                itemClass: "Generic Password", account: "ada@example.com", service: "com.example.App",
                label: "API token", data: Data("s3cr3t-token".utf8)
            )
            let sut = KeychainRow(entry: entry, redaction: .standard, isSelected: true, onSelect: {}, onDelete: {})
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
