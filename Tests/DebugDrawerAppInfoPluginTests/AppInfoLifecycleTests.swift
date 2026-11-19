#if DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerAppInfoPlugin
    import Foundation
    import Testing

    /// Stands in for the 2 s refresh timer: records starts and stops, and ticks when the test says.
    @MainActor
    private final class FakeSamplingTimer: SamplingTimer {
        private(set) var starts = 0
        private(set) var stops = 0
        private var tick: (@MainActor () -> Void)?

        var isRunning: Bool {
            tick != nil
        }

        func start(_ tick: @escaping @MainActor () -> Void) {
            starts += 1
            self.tick = tick
        }

        func stop() {
            stops += 1
            tick = nil
        }

        func deliverTick() {
            tick?()
        }
    }

    /// A wall clock the test moves by hand.
    private final class FakeClock {
        var now: Date

        init(_ now: Date) {
            self.now = now
        }
    }

    @MainActor
    @Suite("App Info refreshes follow the drawer's lifecycle hooks")
    struct AppInfoLifecycleTests {
        @Test("Registering the plugin starts nothing; it refreshes from didBecomeVisible to didBecomeHidden")
        func visibleToHidden() throws {
            let suite = "AppInfoLifecycleTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let drawer = DebugDrawer(defaults: defaults)
            let timer = FakeSamplingTimer()
            let start = Date(timeIntervalSince1970: 1_000)
            let clock = FakeClock(start.addingTimeInterval(10))
            let metrics = AppMetrics(processStart: ProcessStart(date: start, isTraced: false), now: { clock.now }, timer: timer)
            let sut = AppInfoPlugin(
                buildMetadata: AppInfoBuildMetadata(),
                signing: AppSigningStore(source: FakeSigningInformation()),
                metrics: metrics
            )
            let expectedUptimeOnShow: TimeInterval = 20
            let expectedUptimeOnTick: TimeInterval = 22

            drawer.registerGlobal(sut)
            let runningOnceRegistered = timer.isRunning
            clock.now = start.addingTimeInterval(20)
            drawer.pluginContentDidAppear(id: sut.id)
            let uptimeOnShow = metrics.uptime
            clock.now = start.addingTimeInterval(22)
            timer.deliverTick()
            let uptimeOnTick = metrics.uptime
            drawer.pluginContentDidDisappear(id: sut.id)

            #expect(!runningOnceRegistered)
            #expect(uptimeOnShow == expectedUptimeOnShow)
            #expect(uptimeOnTick == expectedUptimeOnTick)
            #expect(timer.starts == 1)
            #expect(timer.stops == 1)
            #expect(!timer.isRunning)
        }

        @Test("Two drawers showing the plugin start the timer once, and it stops only when both hide it")
        func twoDrawers() throws {
            let firstSuite = "AppInfoLifecycleTests.\(UUID().uuidString)"
            let secondSuite = "AppInfoLifecycleTests.\(UUID().uuidString)"
            let firstDefaults = try #require(UserDefaults(suiteName: firstSuite))
            let secondDefaults = try #require(UserDefaults(suiteName: secondSuite))
            defer {
                firstDefaults.removePersistentDomain(forName: firstSuite)
                secondDefaults.removePersistentDomain(forName: secondSuite)
            }
            let first = DebugDrawer(defaults: firstDefaults)
            let second = DebugDrawer(defaults: secondDefaults)
            let timer = FakeSamplingTimer()
            let sut = AppInfoPlugin(
                buildMetadata: AppInfoBuildMetadata(),
                signing: AppSigningStore(source: FakeSigningInformation()),
                metrics: AppMetrics(processStart: nil, now: Date.init, timer: timer)
            )
            first.registerGlobal(sut)
            second.registerGlobal(sut)

            first.pluginContentDidAppear(id: sut.id)
            second.pluginContentDidAppear(id: sut.id)
            first.pluginContentDidDisappear(id: sut.id)
            let runningWhileTheSecondShowsIt = timer.isRunning
            second.pluginContentDidDisappear(id: sut.id)

            #expect(runningWhileTheSecondShowsIt)
            #expect(timer.starts == 1)
            #expect(timer.stops == 1)
            #expect(!timer.isRunning)
        }

        @Test("Once the plugin is hidden, the production timer is cancelled")
        func productionTimerStops() throws {
            let suite = "AppInfoLifecycleTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let drawer = DebugDrawer(defaults: defaults)
            let timer = RunLoopSamplingTimer(interval: 2)
            let sut = AppInfoPlugin(
                buildMetadata: AppInfoBuildMetadata(),
                signing: AppSigningStore(source: FakeSigningInformation()),
                metrics: AppMetrics(processStart: nil, now: Date.init, timer: timer)
            )
            drawer.registerGlobal(sut)

            drawer.pluginContentDidAppear(id: sut.id)
            let timerWhileShown = timer.cancellable
            drawer.pluginContentDidDisappear(id: sut.id)

            #expect(timerWhileShown != nil)
            #expect(timer.cancellable == nil)
        }
    }
#endif
