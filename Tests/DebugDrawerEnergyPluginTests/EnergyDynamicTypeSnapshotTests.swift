// iOS scales text with Dynamic Type, so the large-text snapshots run on the iOS simulator.
#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    @testable import DebugDrawerEnergyPlugin

    // ImageRenderer draws the view without a window, at a fixed scale and the drawer's 316 pt
    // width, so the reference doesn't depend on which simulator runs it.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct EnergyDynamicTypeSnapshotTests {
        @Test("The readout stays readable at the default and a large accessibility text size",
              arguments: [DynamicTypeSize.large, .accessibility3])
        func readout(size: DynamicTypeSize) throws {
            let reading = EnergyReading(
                cpuUsage: 23.4,
                cpuHistory: [4, 6, 12, 35, 80, 41, 18, 9, 22, 23.4],
                batteryLevel: 64,
                batteryHistory: [66, 66, 65, 65, 65, 64, 64],
                isCharging: false,
                powerSource: "Battery",
                thermalState: .fair
            )
            let sut = EnergyReadout(reading: reading, processorCount: 6)
            let renderer = ImageRenderer(content: sut
                .frame(width: 316, alignment: .leading)
                .padding()
                .background(.background)
                .environment(\.dynamicTypeSize, size))
            renderer.scale = 2

            let actual = try #require(renderer.uiImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(size)")
        }
    }
#endif
