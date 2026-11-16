// Views render on the Mac; the snapshot packages are linked on Apple platforms only.
#if os(macOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    @testable import DebugDrawerPerformancePlugin

    // ImageRenderer draws the view without a window, at a fixed scale, in the color scheme the
    // test asks for, so a snapshot doesn't depend on the Mac's own appearance or display. macOS
    // doesn't scale text with Dynamic Type, so the Mac pins light and dark only.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct PerformanceSnapshotTests {
        @Test("While monitoring, the readout shows the frame rate and memory, their sparklines and the stats", arguments: [ColorScheme.light, .dark])
        func readout(colorScheme: ColorScheme) throws {
            let sut = PerformanceReadout(
                fps: 58,
                fpsHistory: [60, 60, 58, 41, 59, 60, 30, 55, 60, 60, 60, 58],
                memoryMB: 182.4,
                memoryHistory: [150, 152, 158, 161, 170, 168, 175, 180, 179, 182.4]
            )
            let renderer = ImageRenderer(content: sut
                .frame(width: 320, alignment: .leading)
                .padding()
                .background(.background)
                .environment(\.colorScheme, colorScheme))
            renderer.scale = 2

            let actual = try #require(renderer.nsImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
        }

        @Test("The HUD readout shows the frame rate, colored, and memory on one line", arguments: [ColorScheme.light, .dark])
        func hudReadout(colorScheme: ColorScheme) throws {
            let sut = PerformanceHUDReadout(fps: 41, memoryMB: 182.4)
            let renderer = ImageRenderer(content: sut
                .padding()
                .background(.background)
                .environment(\.colorScheme, colorScheme))
            renderer.scale = 2

            let actual = try #require(renderer.nsImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
        }

        @Test("The frame-rate sparkline draws its samples", arguments: [ColorScheme.light, .dark])
        func sparkline(colorScheme: ColorScheme) throws {
            let samples = [60, 60, 58, 41, 59, 60, 30, 55, 60, 60, 60, 57]
            let sut = IntSparkline(data: samples, color: .green, height: 30)
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
