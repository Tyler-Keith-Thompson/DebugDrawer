#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerAppInfoPlugin
    import SwiftUI
    import Testing
    import ViewInspector

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct AppInfoProcessStartTests {
        /// A wall clock the test moves by hand.
        private final class FakeClock: WallClock {
            var now: Date
            init(_ now: Date) { self.now = now }
        }

        private func model(start: ProcessStart?, clock: FakeClock = FakeClock(Date())) -> AppInfoModel {
            AppInfoModel(
                bundle: FakeBundleInfoSource(),
                device: _DeviceInfoSource(),
                process: FakeProcessMetricsSource(start: start),
                signing: FakeSigningInformation(),
                clock: clock
            )
        }

        private func texts(_ model: AppInfoModel) throws -> [String] {
            let view = AppInfoPluginView(transport: .direct(to: model))
            return try view.inspect().findAll(ViewType.Text.self).map { try $0.string() }
        }

        @Test("Uptime counts from the process's start, not from when the model was created")
        func uptimeCountsFromProcessStartNotFromWhenMetricsAreCreated() throws {
            let start = ProcessStart(date: Date(timeIntervalSince1970: 1_000_000), isTraced: false)
            let clock = FakeClock(start.date.addingTimeInterval(5))
            let early = model(start: start, clock: clock)
            early.refresh()

            // The drawer is first opened ten minutes later.
            clock.now = start.date.addingTimeInterval(600)
            let late = model(start: start, clock: clock)
            late.refresh()
            early.refresh()

            #expect(late.snapshot.uptime == 600)
            #expect(early.snapshot.uptime == 600)
            #expect(try texts(late).contains("10m 0s"))
            #expect(try texts(late).contains(AppInfoFacts.launchFormatter.string(from: start.date)),
                    "Launched should show the process start, whenever the model was created")
        }

        @Test("The process start comes from kinfo_proc, shortly before this test, and the default process source uses it")
        func processStartComesFromKinfoProc() throws {
            let start = try #require(ProcessStart.current(), "kinfo_proc gave no start time")
            let sut = AppInfoModel(bundle: FakeBundleInfoSource(), device: FakeDeviceInfoSource(), process: _ProcessMetricsSource())

            sut.refresh()

            // This test process started before this test ran, and not long before.
            #expect(start.date < Date())
            #expect(start.date > Date().addingTimeInterval(-3600))
            #expect(try #require(sut.snapshot.uptime) > 0)
            #expect(sut.snapshot.processStart?.date == start.date)
        }

        @Test("The Debugger row says Attached or Not attached from the process, and there is no hardcoded Debug row")
        func debuggerRowIsComputedNotHardcoded() throws {
            let attached = model(start: .init(date: Date(), isTraced: true))
            let detached = model(start: .init(date: Date(), isTraced: false))
            attached.refresh()
            detached.refresh()
            #expect(try texts(attached).contains("Attached"))
            #expect(try texts(detached).contains("Not attached"))
            #expect(try !texts(detached).contains("Debug"), "the hardcoded Debug: Yes row is gone")
        }

        @Test("Without a process start, Uptime and Launched are listed with no made-up value")
        func withoutProcessStartUptimeAndLaunchShowADash() throws {
            let sut = model(start: nil)
            sut.refresh()
            #expect(sut.snapshot.uptime == nil)
            let shown = try texts(sut)
            #expect(shown.contains("Uptime"))
            #expect(shown.contains("Launched"))
            #expect(!shown.contains("0s"), "no made-up uptime: \(shown)")
        }

        @Test("The Sandbox row is shown on macOS only")
        func sandboxRowIsShownOnlyOnMacOS() throws {
            let sut = model(start: nil)
            sut.refresh()
            let shown = try texts(sut)
            #if os(macOS)
                #expect(shown.contains("Sandbox"))
            #else
                #expect(!shown.contains("Sandbox"))
            #endif
        }
    }
#endif
