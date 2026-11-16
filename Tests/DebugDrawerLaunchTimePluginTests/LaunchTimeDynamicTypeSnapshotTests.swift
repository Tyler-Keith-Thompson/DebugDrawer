// iOS scales text with Dynamic Type, so the large-text snapshots run on the iOS simulator.
#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    @testable import DebugDrawerLaunchTimePlugin

    // ImageRenderer draws the view without a window, at a fixed scale and width, so the
    // reference doesn't depend on which simulator runs it.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct LaunchTimeDynamicTypeSnapshotTests {
        @Test("The measured launch time stays readable at a large accessibility text size")
        func measured() throws {
            // Process start at 100.0 s of uptime, install at 100.4 s, first frame at 100.9 s.
            var uptimes = [100.4, 100.9]
            let tracker = LaunchTimeTracker(clock: { uptimes.removeFirst() }, processStartUptime: 100.0)
            tracker.recordFirstFrame()
            let sut = LaunchTimePluginView(tracker: tracker)
            let renderer = ImageRenderer(content: sut
                .frame(width: 320, alignment: .leading)
                .padding()
                .background(.background)
                .environment(\.dynamicTypeSize, .accessibility3))
            renderer.scale = 2

            let actual = try #require(renderer.uiImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "accessibility3")
        }

        @Test("The still-measuring message stays readable at a large accessibility text size")
        func measuring() throws {
            let tracker = LaunchTimeTracker(clock: { 100.4 }, processStartUptime: 100.0)
            let sut = LaunchTimePluginView(tracker: tracker)
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
