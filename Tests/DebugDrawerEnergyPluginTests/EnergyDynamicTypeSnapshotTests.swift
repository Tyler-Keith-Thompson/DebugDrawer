// iOS scales text with Dynamic Type, so the large-text snapshots run on the iOS simulator.
#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    @testable import DebugDrawerEnergyPlugin

    // ImageRenderer draws the view without a window, at a fixed scale and width, so the
    // reference doesn't depend on which simulator runs it.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct EnergyDynamicTypeSnapshotTests {
        @Test("Before monitoring starts, the switch stays readable at a large accessibility text size")
        func idle() throws {
            let sut = EnergyPluginView(monitor: EnergyMonitor(batteryMonitoring: nil))
            let renderer = ImageRenderer(content: sut
                .frame(width: 320, alignment: .leading)
                .padding()
                .background(.background)
                .environment(\.dynamicTypeSize, .accessibility3))
            renderer.scale = 2

            let actual = try #require(renderer.uiImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "accessibility3")
        }

        @Test("The sparkline keeps its height at a large accessibility text size")
        func sparkline() throws {
            let samples: [Double] = [12, 18, 15, 40, 72, 65, 30, 22, 25, 90, 55, 20]
            let sut = EnergySparkline(data: samples, color: .blue, maxValue: 100).frame(height: 30)
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
