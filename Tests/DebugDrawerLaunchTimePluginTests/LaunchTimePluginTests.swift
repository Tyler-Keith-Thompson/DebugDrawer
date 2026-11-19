#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerLaunchTimePlugin
    import Foundation
    import SwiftUI
    import Testing
    import ViewInspector

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct LaunchTimePluginTests {
        /// A clock the test moves by hand.
        private final class FakeClock: UptimeClock {
            var now: TimeInterval
            init(_ now: TimeInterval) { self.now = now }
            var uptime: TimeInterval { now }
        }

        /// A process that started at `uptime`, or one whose start can't be read.
        private struct FakeProcessStart: ProcessStartReader {
            let uptime: TimeInterval?
            func processStartUptime() -> TimeInterval? { uptime }
        }

        private func texts(_ view: LaunchTimePluginView) throws -> [String] {
            try view.inspect().findAll(ViewType.Text.self).map { try $0.string() }
        }

        @Test("Opening the drawer late, and again later, doesn't change the launch times it shows")
        func openingTheDrawerLateDoesNotChangeLaunchTimes() throws {
            let clock = FakeClock(100.4)
            // Process started at 100.0, the app installed at 100.4, first frame at 100.9.
            let model = LaunchTimeModel(clock: clock, processStart: FakeProcessStart(uptime: 100.0))
            clock.now = 100.9
            model.perform(LaunchTimeCommand(.recordFirstFrame))

            // The drawer is opened two minutes later, and again after that.
            clock.now = 220.0
            let firstOpen = try texts(LaunchTimePluginView(transport: .direct(to: model)))
            clock.now = 400.0
            model.perform(LaunchTimeCommand(.recordFirstFrame))
            let secondOpen = try texts(LaunchTimePluginView(transport: .direct(to: model)))

            for shown in [firstOpen, secondOpen] {
                #expect(shown.contains("900 ms"), "total should be 900 ms: \(shown)")
                #expect(shown.contains("400 ms"), "pre-main should be 400 ms: \(shown)")
                #expect(shown.contains("500 ms"), "app init to first frame should be 500 ms: \(shown)")
            }
            #expect(abs((model.snapshot.totalLaunchTime ?? 0) - 0.9) <= 1e-9)
            #expect(abs((model.snapshot.preMainDuration ?? 0) - 0.4) <= 1e-9)
            #expect(abs((model.snapshot.appInitToFirstFrame ?? 0) - 0.5) <= 1e-9)
        }

        @Test("Showing the plugin doesn't record the first frame; it shows Measuring… until one is")
        func showingThePluginDoesNotRecordTheFirstFrame() throws {
            let clock = FakeClock(10)
            let model = LaunchTimeModel(clock: clock, processStart: FakeProcessStart(uptime: 9))
            clock.now = 500
            let shown = try texts(LaunchTimePluginView(transport: .direct(to: model)))
            #expect(model.firstFrameUptime == nil)
            #expect(shown.contains("Measuring…"), "\(shown)")
        }

        @Test("The first frame is recorded when the main run loop goes idle, and later passes don't move it")
        func firstFrameIsRecordedWhenTheMainRunLoopGoesIdle() async throws {
            let clock = FakeClock(50)
            let model = LaunchTimeModel(clock: clock, processStart: FakeProcessStart(uptime: 49), firstFrameObserver: _FirstFrameObserver())

            clock.now = 50.25
            model.waitForFirstFrame()
            // The published value replays on subscription, so a frame recorded first isn't missed.
            // No operator closure: the iterator asks for values off the main actor.
            for await uptime in model.$firstFrameUptime.values where uptime != nil {
                break
            }
            #expect(model.firstFrameUptime == 50.25)

            // Later run-loop passes don't move it.
            clock.now = 99
            model.waitForFirstFrame()
            #expect(model.firstFrameUptime == 50.25)
        }

        @Test("Pre-main runs from the process start kinfo_proc reports to when the app initialized")
        func preMainUsesProcessStartFromKinfoProc() throws {
            let wallStart = try #require(_ProcessStartReader().processStartWallClock(), "kinfo_proc gave no start time")
            let now = Date().timeIntervalSince1970
            // This test process started before this test ran, and not long before.
            #expect(wallStart < now)
            #expect(wallStart > now - 3600)

            let startUptime = try #require(_ProcessStartReader().processStartUptime())
            let model = LaunchTimeModel()
            #expect(abs((model.processStartUptime ?? 0) - startUptime) <= 0.01)
            #expect(abs((model.snapshot.preMainDuration ?? -1) - (model.appInitUptime - startUptime)) <= 0.01)
            #expect((model.snapshot.preMainDuration ?? -1) > 0)
        }

        @Test("Without a process start there is no pre-main or total, only app init to first frame")
        func noProcessStartShowsNoPreMainOrTotal() throws {
            let clock = FakeClock(10)
            let model = LaunchTimeModel(clock: clock, processStart: FakeProcessStart(uptime: nil))
            clock.now = 11
            model.perform(LaunchTimeCommand(.recordFirstFrame))
            #expect(model.snapshot.preMainDuration == nil)
            #expect(model.snapshot.totalLaunchTime == nil)
            #expect(abs((model.snapshot.appInitToFirstFrame ?? 0) - 1) <= 1e-9)
            let shown = try texts(LaunchTimePluginView(transport: .direct(to: model)))
            #expect(!shown.contains { $0.hasPrefix("Pre-main") }, "\(shown)")
        }
    }
#endif
