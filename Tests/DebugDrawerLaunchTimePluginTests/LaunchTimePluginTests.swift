#if DEBUG
    import Combine
    @testable import DebugDrawerLaunchTimePlugin
    import SwiftUI
    import ViewInspector
    import XCTest

    @MainActor
    final class LaunchTimePluginTests: XCTestCase {
        /// A clock the test moves by hand.
        private final class FakeClock {
            var now: TimeInterval
            init(_ now: TimeInterval) { self.now = now }
        }

        private func texts(_ view: LaunchTimePluginView) throws -> [String] {
            try view.inspect().findAll(ViewType.Text.self).map { try $0.string() }
        }

        func testOpeningTheDrawerLateDoesNotChangeLaunchTimes() throws {
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
                XCTAssertTrue(shown.contains("900 ms"), "total should be 900 ms: \(shown)")
                XCTAssertTrue(shown.contains("400 ms"), "pre-main should be 400 ms: \(shown)")
                XCTAssertTrue(shown.contains("500 ms"), "app init to first frame should be 500 ms: \(shown)")
            }
            XCTAssertEqual(tracker.totalLaunchTime ?? 0, 0.9, accuracy: 1e-9)
            XCTAssertEqual(tracker.preMainDuration ?? 0, 0.4, accuracy: 1e-9)
            XCTAssertEqual(tracker.appInitToFirstFrame ?? 0, 0.5, accuracy: 1e-9)
        }

        func testShowingThePluginDoesNotRecordTheFirstFrame() throws {
            let clock = FakeClock(10)
            let tracker = LaunchTimeTracker(clock: { clock.now }, processStartUptime: 9)
            clock.now = 500
            let shown = try texts(LaunchTimePluginView(tracker: tracker))
            XCTAssertNil(tracker.firstFrameUptime)
            XCTAssertTrue(shown.contains("Measuring…"), "\(shown)")
        }

        func testFirstFrameIsRecordedWhenTheMainRunLoopGoesIdle() async throws {
            let clock = FakeClock(50)
            let tracker = LaunchTimeTracker(clock: { clock.now }, processStartUptime: 49)
            let recorded = expectation(description: "first frame recorded")
            let cancellable = tracker.$firstFrameUptime.compactMap { $0 }.sink { _ in recorded.fulfill() }
            defer { cancellable.cancel() }

            clock.now = 50.25
            tracker.observeFirstFrame()
            await fulfillment(of: [recorded], timeout: 5)
            XCTAssertEqual(tracker.firstFrameUptime, 50.25)

            // Later run-loop passes don't move it.
            clock.now = 99
            tracker.observeFirstFrame()
            XCTAssertEqual(tracker.firstFrameUptime, 50.25)
        }

        func testPreMainUsesProcessStartFromKinfoProc() throws {
            let wallStart = try XCTUnwrap(LaunchTimeTracker.processStartWallClock(), "kinfo_proc gave no start time")
            let now = Date().timeIntervalSince1970
            // This test process started before this test ran, and not long before.
            XCTAssertLessThan(wallStart, now)
            XCTAssertGreaterThan(wallStart, now - 3600)

            let startUptime = try XCTUnwrap(LaunchTimeTracker.processStartUptimeFromKernel())
            let tracker = LaunchTimeTracker()
            XCTAssertEqual(tracker.processStartUptime ?? 0, startUptime, accuracy: 0.01)
            XCTAssertEqual(tracker.preMainDuration ?? -1, tracker.appInitUptime - startUptime, accuracy: 0.01)
            XCTAssertGreaterThan(tracker.preMainDuration ?? -1, 0)
        }

        func testNoProcessStartShowsNoPreMainOrTotal() throws {
            let clock = FakeClock(10)
            let tracker = LaunchTimeTracker(clock: { clock.now }, processStartUptime: nil)
            clock.now = 11
            tracker.recordFirstFrame()
            XCTAssertNil(tracker.preMainDuration)
            XCTAssertNil(tracker.totalLaunchTime)
            XCTAssertEqual(tracker.appInitToFirstFrame ?? 0, 1, accuracy: 1e-9)
            let shown = try texts(LaunchTimePluginView(tracker: tracker))
            XCTAssertFalse(shown.contains { $0.hasPrefix("Pre-main") }, "\(shown)")
        }
    }
#endif
