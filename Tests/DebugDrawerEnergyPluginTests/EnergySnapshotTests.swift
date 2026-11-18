// Views render on the Mac; the snapshot packages are linked on Apple platforms only.
#if os(macOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    @testable import DebugDrawerEnergyPlugin

    // ImageRenderer draws the view without a window, at a fixed scale and the drawer's 316 pt
    // width, in the color scheme the test asks for, so a snapshot doesn't depend on the Mac's own
    // appearance or display. macOS doesn't scale text with Dynamic Type, so the Mac pins light and
    // dark only.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct EnergySnapshotTests {
        @Test("The readout shows the CPU load and its history, the battery, and the thermal state and power source",
              arguments: [ColorScheme.light, .dark])
        func readout(colorScheme: ColorScheme) throws {
            let reading = EnergyReading(
                cpuUsage: 23.4,
                cpuHistory: [4, 6, 12, 35, 80, 41, 18, 9, 22, 23.4],
                batteryLevel: 64,
                batteryHistory: [66, 66, 65, 65, 65, 64, 64],
                isCharging: false,
                powerSource: "Battery Power",
                thermalState: .fair
            )
            let sut = EnergyReadout(reading: reading, processorCount: 8)
            let renderer = ImageRenderer(content: sut
                .frame(width: 316, alignment: .leading)
                .padding()
                .background(.background)
                .environment(\.colorScheme, colorScheme))
            renderer.scale = 2

            let actual = try #require(renderer.nsImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
        }
    }
#endif
