// iOS scales text with Dynamic Type, so the large-text snapshots run on the iOS simulator.
#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    @testable import DebugDrawerAccessibilityPlugin

    // ImageRenderer draws the view without a window, at a fixed scale and width, so the
    // reference doesn't depend on which simulator runs it.
    // The section follows AccessibilityOverrides.shared, which the suites beside it set.
    extension SharedAccessibilityOverrides {
        @MainActor
        @Suite(.timeLimit(.minutes(1)))
        struct AccessibilityDynamicTypeSnapshotTests {
            @Test("The settings section stays readable at a large accessibility text size")
            func settingsSection() throws {
                let sut = AccessibilitySettingsSection(system: .init(reduceMotion: true, increaseContrast: true))
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
    }
#endif
