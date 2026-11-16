#if DEBUG
    @testable import DebugDrawerAppInfoPlugin
    import SwiftUI
    import ViewInspector
    import XCTest

    @MainActor
    final class AppInfoProcessStartTests: XCTestCase {
        /// A wall clock the test moves by hand.
        private final class FakeClock {
            var now: Date
            init(_ now: Date) { self.now = now }
        }

        private func texts(_ metrics: AppMetrics) throws -> [String] {
            try AppInfoPluginView(metrics: metrics).inspect().findAll(ViewType.Text.self).map { try $0.string() }
        }

        func testUptimeCountsFromProcessStartNotFromWhenMetricsAreCreated() throws {
            let start = ProcessStart(date: Date(timeIntervalSince1970: 1_000_000), isTraced: false)
            let clock = FakeClock(start.date.addingTimeInterval(5))
            let early = AppMetrics(processStart: start, now: { clock.now })

            // The drawer is first opened ten minutes later.
            clock.now = start.date.addingTimeInterval(600)
            let late = AppMetrics(processStart: start, now: { clock.now })
            early.refresh()

            XCTAssertEqual(late.uptime, 600)
            XCTAssertEqual(early.uptime, 600)
            XCTAssertTrue(try texts(late).contains("10m 0s"))
            XCTAssertTrue(try texts(late).contains(AppInfoFacts.launchFormatter.string(from: start.date)),
                          "Launched should show the process start, whenever the metrics were created")
        }

        func testProcessStartComesFromKinfoProc() throws {
            let start = try XCTUnwrap(ProcessStart.current(), "kinfo_proc gave no start time")
            // This test process started before this test ran, and not long before.
            XCTAssertLessThan(start.date, Date())
            XCTAssertGreaterThan(start.date, Date().addingTimeInterval(-3600))
            XCTAssertGreaterThan(try XCTUnwrap(AppMetrics.shared.uptime), 0)
            XCTAssertEqual(AppMetrics.shared.processStart?.date, start.date)
        }

        func testDebuggerRowIsComputedNotHardcoded() throws {
            let attached = AppMetrics(processStart: .init(date: Date(), isTraced: true), now: Date.init)
            let detached = AppMetrics(processStart: .init(date: Date(), isTraced: false), now: Date.init)
            XCTAssertTrue(try texts(attached).contains("Attached"))
            XCTAssertTrue(try texts(detached).contains("Not attached"))
            XCTAssertFalse(try texts(detached).contains("Debug"), "the hardcoded Debug: Yes row is gone")
        }

        func testWithoutProcessStartUptimeAndLaunchShowADash() throws {
            let metrics = AppMetrics(processStart: nil, now: Date.init)
            XCTAssertNil(metrics.uptime)
            let shown = try texts(metrics)
            XCTAssertTrue(shown.contains("Uptime"))
            XCTAssertTrue(shown.contains("Launched"))
            XCTAssertFalse(shown.contains("0s"), "no made-up uptime: \(shown)")
        }

        func testSandboxRowIsShownOnlyOnMacOS() throws {
            let shown = try texts(AppMetrics(processStart: nil, now: Date.init))
            #if os(macOS)
                XCTAssertTrue(shown.contains("Sandbox"))
            #else
                XCTAssertFalse(shown.contains("Sandbox"))
            #endif
        }
    }
#endif
