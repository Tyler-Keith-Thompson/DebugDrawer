// Views render on the Mac; the snapshot packages are linked on Apple platforms only.
#if os(macOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    @testable import DebugDrawerPerformancePlugin

    // ImageRenderer draws the view without a window, at a fixed scale and the drawer's 316 pt
    // width, in the color scheme the test asks for, so a snapshot doesn't depend on the Mac's own
    // appearance or display. macOS doesn't scale text with Dynamic Type, so the Mac pins light and
    // dark only.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct PerformanceSnapshotTests {
        @Test("The readout shows frame rate and memory as gauges, their sparklines, the stats and the dropped frames",
              arguments: [ColorScheme.light, .dark])
        func readout(colorScheme: ColorScheme) throws {
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
                .environment(\.colorScheme, colorScheme))
            renderer.scale = 2

            let actual = try #require(renderer.nsImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
        }

        @Test("The HUD readout shows the frame rate, with a glyph while frames drop, and memory on one line", arguments: [ColorScheme.light, .dark])
        func hudReadout(colorScheme: ColorScheme) throws {
            let sut = PerformanceHUDReadout(fps: 41, footprintMB: 182.4)
            let renderer = ImageRenderer(content: sut
                .padding()
                .background(.background)
                .environment(\.colorScheme, colorScheme))
            renderer.scale = 2

            let actual = try #require(renderer.nsImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
        }
    }
#endif
