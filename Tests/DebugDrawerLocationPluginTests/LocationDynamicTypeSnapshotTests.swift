// iOS scales text with Dynamic Type, so the large-text snapshots run on the iOS simulator.
#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    @testable import DebugDrawerLocationPlugin

    // ImageRenderer draws the view without a window, at a fixed scale and width, so the
    // reference doesn't depend on which simulator runs it.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct LocationDynamicTypeSnapshotTests {
        @Test("With spoofing off, the switch stays readable at a large accessibility text size")
        func off() throws {
            let sut = LocationForm(
                isEnabled: .constant(false), latitudeText: .constant(""), longitudeText: .constant(""),
                active: nil, presets: [], onPreset: { _ in }
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

        @Test("With spoofing on, the form stays readable at a large accessibility text size")
        func on() throws {
            let presets = [
                LocationSimulator.PresetLocation(name: "Cupertino", latitude: 37.3349, longitude: -122.009),
                LocationSimulator.PresetLocation(name: "London", latitude: 51.5074, longitude: -0.1278)
            ]
            let sut = LocationForm(
                isEnabled: .constant(true), latitudeText: .constant("37.3349"), longitudeText: .constant("-122.009"),
                active: .init(latitude: 37.3349, longitude: -122.009), presets: presets, onPreset: { _ in }
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
