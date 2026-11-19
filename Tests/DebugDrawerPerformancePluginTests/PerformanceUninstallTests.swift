#if DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerPerformancePlugin
    import Foundation
    import Testing

    /// Stands in for the display link and the 1 s timer: records starts and stops, and ticks when
    /// the test says.
    @MainActor
    private final class TickingSampler: PerformanceSampler {
        private(set) var starts = 0
        private(set) var stops = 0
        private var tick: (@MainActor () -> Void)?

        var isRunning: Bool {
            tick != nil
        }

        func start(
            frame: @escaping @MainActor (TimeInterval, TimeInterval) -> Void,
            tick: @escaping @MainActor () -> Void
        ) {
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

    private struct OneThread: ThreadSampler {
        func sample() -> [ThreadCPU] {
            [ThreadCPU(name: "Main Thread", threadID: 1, cpuUsage: 0.05)]
        }
    }

    @MainActor
    @Suite("Performance drops its history once removed from every drawer")
    struct PerformanceUninstallTests {
        private static func drawer() throws -> (DebugDrawer, () -> Void) {
            let suite = "PerformanceUninstallTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            return (DebugDrawer(defaults: defaults), { defaults.removePersistentDomain(forName: suite) })
        }

        @Test("Unregistering while shown removes the plugin, stops sampling once, and drops the history")
        func disappearsFromTheDrawer() throws {
            let (drawer, cleanUp) = try Self.drawer()
            defer { cleanUp() }
            let sampler = TickingSampler()
            let monitor = PerformanceMonitor(sampler: sampler, threadSampler: OneThread())
            let sut = PerformancePlugin(monitor: monitor)
            drawer.registerGlobal(sut)
            drawer.pluginContentDidAppear(id: sut.id)
            sampler.deliverTick()
            let historyWhileShown = monitor.fpsHistory.count

            drawer.unregisterGlobal(id: sut.id)

            #expect(historyWhileShown == 1)
            #expect(!drawer.globalPlugins.contains { $0.id == sut.id })
            #expect(sampler.stops == 1)
            #expect(!sampler.isRunning)
            #expect(!monitor.isMonitoring)
            #expect(monitor.fpsHistory.isEmpty)
            #expect(monitor.footprintHistory.isEmpty)
            #expect(monitor.threads.isEmpty)
            #expect(monitor.footprintMB == 0)
        }

        @Test("Uninstalling twice is harmless, and a plugin registered again samples again")
        func uninstallTwiceThenReinstall() throws {
            let (drawer, cleanUp) = try Self.drawer()
            defer { cleanUp() }
            let sampler = TickingSampler()
            let sut = PerformancePlugin(monitor: PerformanceMonitor(sampler: sampler, threadSampler: OneThread()))
            drawer.registerGlobal(sut)
            drawer.unregisterGlobal(id: sut.id)

            sut.uninstall(from: drawer)
            drawer.registerGlobal(sut)
            drawer.pluginContentDidAppear(id: sut.id)

            #expect(sampler.starts == 1)
            #expect(sampler.stops == 0)
            #expect(sampler.isRunning)
        }

        @Test("A second drawer still holding the plugin keeps the history")
        func twoDrawers() throws {
            let (first, cleanUpFirst) = try Self.drawer()
            let (second, cleanUpSecond) = try Self.drawer()
            defer {
                cleanUpFirst()
                cleanUpSecond()
            }
            let sampler = TickingSampler()
            let monitor = PerformanceMonitor(sampler: sampler, threadSampler: OneThread())
            let sut = PerformancePlugin(monitor: monitor)
            first.registerGlobal(sut)
            second.registerGlobal(sut)
            second.pluginContentDidAppear(id: sut.id)
            sampler.deliverTick()

            first.unregisterGlobal(id: sut.id)

            #expect(sampler.isRunning)
            #expect(monitor.fpsHistory.count == 1)
        }
    }
#endif
