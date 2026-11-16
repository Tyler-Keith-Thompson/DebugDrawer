// Views render on the Mac; the snapshot packages are linked on Apple platforms only.
#if os(macOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    @testable import DebugDrawerKeychainPlugin

    // ImageRenderer draws the view without a window, at a fixed scale, in the color scheme the
    // test asks for, so a snapshot doesn't depend on the Mac's own appearance or display. macOS
    // doesn't scale text with Dynamic Type, so the Mac pins light and dark only.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct KeychainSnapshotTests {
        @Test("An unselected keychain row shows the account, service and class", arguments: [ColorScheme.light, .dark])
        func unselectedRow(colorScheme: ColorScheme) throws {
            let entry = KeychainEntry(
                itemClass: "Generic Password", account: "ada@example.com", service: "com.example.App",
                label: "API token", data: Data("s3cr3t-token".utf8)
            )
            let sut = KeychainRow(entry: entry, redaction: .standard, isSelected: false, onSelect: {}, onDelete: {})
            let renderer = ImageRenderer(content: sut
                .frame(width: 320, alignment: .leading)
                .padding()
                .background(.background)
                .environment(\.colorScheme, colorScheme))
            renderer.scale = 2

            let actual = try #require(renderer.nsImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
        }

        @Test("A selected keychain row shows the entry's details and its actions", arguments: [ColorScheme.light, .dark])
        func selectedRow(colorScheme: ColorScheme) throws {
            let entry = KeychainEntry(
                itemClass: "Generic Password", account: "ada@example.com", service: "com.example.App",
                label: "API token", data: Data("s3cr3t-token".utf8)
            )
            let sut = KeychainRow(entry: entry, redaction: .standard, isSelected: true, onSelect: {}, onDelete: {})
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
