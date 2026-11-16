// iOS scales text with Dynamic Type, so the large-text snapshots run on the iOS simulator.
#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    @testable import DebugDrawerUserDefaultsPlugin

    // ImageRenderer draws the view without a window, at a fixed scale and width, so the
    // reference doesn't depend on which simulator runs it.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct UserDefaultsDynamicTypeSnapshotTests {
        @Test("An unselected defaults row stays readable at a large accessibility text size")
        func unselectedRow() throws {
            let entry = DefaultsEntry(id: "launchCount", key: "launchCount", value: "12", type: "Int", rawValue: 12)
            let sut = DefaultsEntryRow(entry: entry, redaction: .standard, isSelected: false, onSelect: {}, onSet: { _ in }, onDelete: {})
            let renderer = ImageRenderer(content: sut
                .frame(width: 320, alignment: .leading)
                .padding()
                .background(.background)
                .environment(\.dynamicTypeSize, .accessibility3))
            renderer.scale = 2

            let actual = try #require(renderer.uiImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "accessibility3")
        }

        @Test("A selected string row stays readable at a large accessibility text size")
        func selectedStringRow() throws {
            let entry = DefaultsEntry(id: "username", key: "username", value: "ada", type: "String", rawValue: "ada")
            let sut = DefaultsEntryRow(entry: entry, redaction: .standard, isSelected: true, onSelect: {}, onSet: { _ in }, onDelete: {})
            let renderer = ImageRenderer(content: sut
                .frame(width: 320, alignment: .leading)
                .padding()
                .background(.background)
                .environment(\.dynamicTypeSize, .accessibility3))
            renderer.scale = 2

            let actual = try #require(renderer.uiImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "accessibility3")
        }

        @Test("A selected Boolean row stays readable at a large accessibility text size")
        func selectedBoolRow() throws {
            let entry = DefaultsEntry(
                id: "onboarding.completed", key: "onboarding.completed", value: "true", type: "Bool", rawValue: true
            )
            let sut = DefaultsEntryRow(entry: entry, redaction: .standard, isSelected: true, onSelect: {}, onSet: { _ in }, onDelete: {})
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
