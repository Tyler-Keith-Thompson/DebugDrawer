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
        @Test("The readout, dropped frames included, stays readable at the default and a large accessibility text size",
              arguments: [DynamicTypeSize.large, .accessibility3])
        func readout(size: DynamicTypeSize) throws {
            let sut = PerformanceReadout(
                fps: 58,
                fpsHistory: [60, 60, 58, 41, 59, 60, 30, 55, 60, 60, 60, 58],
                maximumFPS: 60,
                droppedFrames: 29,
                footprintMB: 182.4,
                footprintHistory: [150, 152, 158, 161, 170, 168, 175, 180, 179, 182.4],
                peakFootprintMB: 214.7,
                physicalMemoryMB: 8192
            )
            let renderer = ImageRenderer(content: sut
                .frame(width: 316, alignment: .leading)
                .padding()
                .background(.background)
                .environment(\.dynamicTypeSize, size))
            renderer.scale = 2

            let actual = try #require(renderer.uiImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(size)")
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
    }
#endif
