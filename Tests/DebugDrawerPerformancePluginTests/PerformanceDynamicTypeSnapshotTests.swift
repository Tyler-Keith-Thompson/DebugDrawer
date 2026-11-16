// iOS scales text with Dynamic Type, so the large-text snapshots run on the iOS simulator.
#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    @testable import DebugDrawerPerformancePlugin

    // ImageRenderer draws the view without a window, at a fixed scale and width, so the
    // reference doesn't depend on which simulator runs it.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct PerformanceDynamicTypeSnapshotTests {
        @Test("The readout stays readable at a large accessibility text size")
        func readout() throws {
            let sut = PerformanceReadout(
                fps: 58,
                fpsHistory: [60, 60, 58, 41, 59, 60, 30, 55, 60, 60, 60, 58],
                footprintMB: 182.4,
                footprintHistory: [150, 152, 158, 161, 170, 168, 175, 180, 179, 182.4]
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

        @Test("The HUD readout stays readable at a large accessibility text size")
        func hudReadout() throws {
            let sut = PerformanceHUDReadout(fps: 41, footprintMB: 182.4)
            let renderer = ImageRenderer(content: sut
                .frame(width: 320, alignment: .leading)
                .padding()
                .background(.background)
                .environment(\.dynamicTypeSize, .accessibility3))
            renderer.scale = 2

            let actual = try #require(renderer.uiImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "accessibility3")
        }

        @Test("The frame-rate sparkline keeps its height at a large accessibility text size")
        func sparkline() throws {
            let samples = [60, 60, 58, 41, 59, 60, 30, 55, 60, 60, 60, 57]
            let sut = IntSparkline(data: samples, color: .green, height: 30)
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
