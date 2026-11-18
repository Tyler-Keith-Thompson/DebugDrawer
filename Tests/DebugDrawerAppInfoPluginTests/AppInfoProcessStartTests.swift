#if DEBUG
    @testable import DebugDrawerAppInfoPlugin
    import SwiftUI
    import Testing
    import ViewInspector

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct AppInfoProcessStartTests {
        /// A wall clock the test moves by hand.
        private final class FakeClock {
            var now: Date
            init(_ now: Date) { self.now = now }
        }

        private func texts(_ metrics: AppMetrics) throws -> [String] {
            let signing = AppSigningStore(source: FakeSigningInformation())
            let view = AppInfoPluginView(metrics: metrics, buildMetadata: AppInfoBuildMetadata(), signing: signing)
            return try view.inspect().findAll(ViewType.Text.self).map { try $0.string() }
        }

        @Test("Uptime counts from the process's start, not from when the metrics were created")
        func uptimeCountsFromProcessStartNotFromWhenMetricsAreCreated() throws {
            let start = ProcessStart(date: Date(timeIntervalSince1970: 1_000_000), isTraced: false)
            let clock = FakeClock(start.date.addingTimeInterval(5))
            let early = AppMetrics(processStart: start, now: { clock.now })

            // The drawer is first opened ten minutes later.
            clock.now = start.date.addingTimeInterval(600)
            let late = AppMetrics(processStart: start, now: { clock.now })
            early.refresh()

            #expect(late.uptime == 600)
            #expect(early.uptime == 600)
            #expect(try texts(late).contains("10m 0s"))
            #expect(try texts(late).contains(AppInfoFacts.launchFormatter.string(from: start.date)),
                    "Launched should show the process start, whenever the metrics were created")
        }

        @Test("The process start comes from kinfo_proc, shortly before this test, and the shared metrics use it")
        func processStartComesFromKinfoProc() throws {
            let start = try #require(ProcessStart.current(), "kinfo_proc gave no start time")
            // This test process started before this test ran, and not long before.
            #expect(start.date < Date())
            #expect(start.date > Date().addingTimeInterval(-3600))
            #expect(try #require(AppMetrics.shared.uptime) > 0)
            #expect(AppMetrics.shared.processStart?.date == start.date)
        }

        @Test("The Debugger row says Attached or Not attached from the process, and there is no hardcoded Debug row")
        func debuggerRowIsComputedNotHardcoded() throws {
            let attached = AppMetrics(processStart: .init(date: Date(), isTraced: true), now: Date.init)
            let detached = AppMetrics(processStart: .init(date: Date(), isTraced: false), now: Date.init)
            #expect(try texts(attached).contains("Attached"))
            #expect(try texts(detached).contains("Not attached"))
            #expect(try !texts(detached).contains("Debug"), "the hardcoded Debug: Yes row is gone")
        }

        @Test("Without a process start, Uptime and Launched are listed with no made-up value")
        func withoutProcessStartUptimeAndLaunchShowADash() throws {
            let metrics = AppMetrics(processStart: nil, now: Date.init)
            #expect(metrics.uptime == nil)
            let shown = try texts(metrics)
            #expect(shown.contains("Uptime"))
            #expect(shown.contains("Launched"))
            #expect(!shown.contains("0s"), "no made-up uptime: \(shown)")
        }

        @Test("The Sandbox row is shown on macOS only")
        func sandboxRowIsShownOnlyOnMacOS() throws {
            let shown = try texts(AppMetrics(processStart: nil, now: Date.init))
            #if os(macOS)
                #expect(shown.contains("Sandbox"))
            #else
                #expect(!shown.contains("Sandbox"))
            #endif
        }
    }
#endif
