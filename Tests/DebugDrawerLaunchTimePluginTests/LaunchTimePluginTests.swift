#if DEBUG
    @testable import DebugDrawerLaunchTimePlugin
    import SwiftUI
    import Testing
    import ViewInspector

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct LaunchTimePluginTests {
        /// A clock the test moves by hand.
        private final class FakeClock {
            var now: TimeInterval
            init(_ now: TimeInterval) { self.now = now }
        }

        private func texts(_ view: LaunchTimePluginView) throws -> [String] {
            try view.inspect().findAll(ViewType.Text.self).map { try $0.string() }
        }

        @Test("Opening the drawer late, and again later, doesn't change the launch times it shows")
        func openingTheDrawerLateDoesNotChangeLaunchTimes() throws {
            let clock = FakeClock(100.4)
            // Process started at 100.0, the app installed at 100.4, first frame at 100.9.
            let tracker = LaunchTimeTracker(clock: { clock.now }, processStartUptime: 100.0)
            clock.now = 100.9
            tracker.recordFirstFrame()

            // The drawer is opened two minutes later, and again after that.
            clock.now = 220.0
            let firstOpen = try texts(LaunchTimePluginView(tracker: tracker))
            clock.now = 400.0
            tracker.recordFirstFrame()
            let secondOpen = try texts(LaunchTimePluginView(tracker: tracker))

            for shown in [firstOpen, secondOpen] {
                #expect(shown.contains("900 ms"), "total should be 900 ms: \(shown)")
                #expect(shown.contains("400 ms"), "pre-main should be 400 ms: \(shown)")
                #expect(shown.contains("500 ms"), "app init to first frame should be 500 ms: \(shown)")
            }
            #expect(abs((tracker.totalLaunchTime ?? 0) - 0.9) <= 1e-9)
            #expect(abs((tracker.preMainDuration ?? 0) - 0.4) <= 1e-9)
            #expect(abs((tracker.appInitToFirstFrame ?? 0) - 0.5) <= 1e-9)
        }

        @Test("Showing the plugin doesn't record the first frame; it shows Measuring… until one is")
        func showingThePluginDoesNotRecordTheFirstFrame() throws {
            let clock = FakeClock(10)
            let tracker = LaunchTimeTracker(clock: { clock.now }, processStartUptime: 9)
            clock.now = 500
            let shown = try texts(LaunchTimePluginView(tracker: tracker))
            #expect(tracker.firstFrameUptime == nil)
            #expect(shown.contains("Measuring…"), "\(shown)")
        }

        @Test("The first frame is recorded when the main run loop goes idle, and later passes don't move it")
        func firstFrameIsRecordedWhenTheMainRunLoopGoesIdle() async throws {
            let clock = FakeClock(50)
            let tracker = LaunchTimeTracker(clock: { clock.now }, processStartUptime: 49)

            clock.now = 50.25
            tracker.observeFirstFrame()
            // The published value replays on subscription, so a frame recorded first isn't missed.
            // No operator closure: the iterator asks for values off the main actor.
            for await uptime in tracker.$firstFrameUptime.values where uptime != nil {
                break
            }
            #expect(tracker.firstFrameUptime == 50.25)

            // Later run-loop passes don't move it.
            clock.now = 99
            tracker.observeFirstFrame()
            #expect(tracker.firstFrameUptime == 50.25)
        }

        @Test("Pre-main runs from the process start kinfo_proc reports to when the app initialized")
        func preMainUsesProcessStartFromKinfoProc() throws {
            let wallStart = try #require(LaunchTimeTracker.processStartWallClock(), "kinfo_proc gave no start time")
            let now = Date().timeIntervalSince1970
            // This test process started before this test ran, and not long before.
            #expect(wallStart < now)
            #expect(wallStart > now - 3600)

            let startUptime = try #require(LaunchTimeTracker.processStartUptimeFromKernel())
            let tracker = LaunchTimeTracker()
            #expect(abs((tracker.processStartUptime ?? 0) - startUptime) <= 0.01)
            #expect(abs((tracker.preMainDuration ?? -1) - (tracker.appInitUptime - startUptime)) <= 0.01)
            #expect((tracker.preMainDuration ?? -1) > 0)
        }

        @Test("Without a process start there is no pre-main or total, only app init to first frame")
        func noProcessStartShowsNoPreMainOrTotal() throws {
            let clock = FakeClock(10)
            let tracker = LaunchTimeTracker(clock: { clock.now }, processStartUptime: nil)
            clock.now = 11
            tracker.recordFirstFrame()
            #expect(tracker.preMainDuration == nil)
            #expect(tracker.totalLaunchTime == nil)
            #expect(abs((tracker.appInitToFirstFrame ?? 0) - 1) <= 1e-9)
            let shown = try texts(LaunchTimePluginView(tracker: tracker))
            #expect(!shown.contains { $0.hasPrefix("Pre-main") }, "\(shown)")
        }
    }
#endif
