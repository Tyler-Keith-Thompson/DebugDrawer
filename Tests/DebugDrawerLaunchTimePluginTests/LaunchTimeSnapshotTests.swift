// Views render on the Mac; the snapshot packages are linked on Apple platforms only.
#if os(macOS)
    import DebugDrawer
    import SnapshotTesting
    import SwiftUI
    import Testing
    @testable import DebugDrawerLaunchTimePlugin

    // ImageRenderer draws the view without a window, at a fixed scale, in the color scheme the
    // test asks for, so a snapshot doesn't depend on the Mac's own appearance or display. macOS
    // doesn't scale text with Dynamic Type, so the Mac pins light and dark only.
    /// A clock that reads out the uptimes it is given, one a read.
    private final class FakeClock: UptimeClock {
        private var uptimes: [TimeInterval]
        init(_ uptimes: [TimeInterval]) { self.uptimes = uptimes }
        var uptime: TimeInterval { uptimes.removeFirst() }
    }

    /// A process that started at `uptime`.
    private struct FakeProcessStart: ProcessStartReader {
        let uptime: TimeInterval?
        func processStartUptime() -> TimeInterval? { uptime }
    }

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct LaunchTimeSnapshotTests {
        @Test("Once the first frame is in, the plugin shows the total and its two phases", arguments: [ColorScheme.light, .dark])
        func measured(colorScheme: ColorScheme) throws {
            // Process start at 100.0 s of uptime, install at 100.4 s, first frame at 100.9 s.
            let model = LaunchTimeModel(clock: FakeClock([100.4, 100.9]), processStart: FakeProcessStart(uptime: 100.0))
            model.perform(LaunchTimeCommand(.recordFirstFrame))
            let sut = LaunchTimePluginView(transport: .direct(to: model))
            let renderer = ImageRenderer(content: sut
                .frame(width: 320, alignment: .leading)
                .padding()
                .background(.background)
                .environment(\.colorScheme, colorScheme))
            renderer.scale = 2

            let actual = try #require(renderer.nsImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
        }

        @Test("Before the first frame, the plugin says it is still measuring", arguments: [ColorScheme.light, .dark])
        func measuring(colorScheme: ColorScheme) throws {
            let model = LaunchTimeModel(clock: FakeClock([100.4]), processStart: FakeProcessStart(uptime: 100.0))
            let sut = LaunchTimePluginView(transport: .direct(to: model))
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
