#if DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerEnergyPlugin
    import Foundation
    import Testing

    /// Stands in for the 1 s timer: records starts and stops, and ticks when the test says.
    @MainActor
    private final class TickingTimer: SamplingTimer {
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

    @MainActor
    @Suite("Energy drops its history once removed from every drawer, unless the app samples")
    struct EnergyUninstallTests {
        private static func drawer() throws -> (DebugDrawer, () -> Void) {
            let suite = "EnergyUninstallTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            return (DebugDrawer(defaults: defaults), { defaults.removePersistentDomain(forName: suite) })
        }

        @Test("Unregistering while shown removes the plugin, stops sampling once, and drops the history")
        func disappearsFromTheDrawer() throws {
            let (drawer, cleanUp) = try Self.drawer()
            defer { cleanUp() }
            let timer = TickingTimer()
            let monitor = EnergyMonitor(batteryMonitoring: nil, timer: timer)
            let sut = EnergyPlugin(monitor: monitor)
            drawer.registerGlobal(sut)
            drawer.pluginContentDidAppear(id: sut.id)
            timer.deliverTick()
            let historyWhileShown = monitor.cpuHistory.count

            drawer.unregisterGlobal(id: sut.id)

            #expect(historyWhileShown == 2)
            #expect(!drawer.globalPlugins.contains { $0.id == sut.id })
            #expect(timer.stops == 1)
            #expect(!timer.isRunning)
            #expect(!monitor.isMonitoring)
            #expect(monitor.cpuHistory.isEmpty)
            #expect(monitor.batteryHistory.isEmpty)
            #expect(monitor.powerSource == "Unknown")
        }

        @Test("The app's start() keeps sampling, and its history, after the plugin is removed")
        func appSamplingOutlivesUninstall() throws {
            let (drawer, cleanUp) = try Self.drawer()
            defer { cleanUp() }
            let timer = TickingTimer()
            let monitor = EnergyMonitor(batteryMonitoring: nil, timer: timer)
            let sut = EnergyPlugin(monitor: monitor)
            drawer.registerGlobal(sut)
            monitor.start()
            defer { monitor.stop() }

            drawer.unregisterGlobal(id: sut.id)

            #expect(timer.isRunning)
            #expect(monitor.cpuHistory.count == 1)
        }

        @Test("Uninstalling twice is harmless, and a plugin registered again samples again")
        func uninstallTwiceThenReinstall() throws {
            let (drawer, cleanUp) = try Self.drawer()
            defer { cleanUp() }
            let timer = TickingTimer()
            let sut = EnergyPlugin(monitor: EnergyMonitor(batteryMonitoring: nil, timer: timer))
            drawer.registerGlobal(sut)
            drawer.unregisterGlobal(id: sut.id)

            sut.uninstall(from: drawer)
            drawer.registerGlobal(sut)
            drawer.pluginContentDidAppear(id: sut.id)

            #expect(timer.starts == 1)
            #expect(timer.stops == 0)
            #expect(timer.isRunning)
        }
    }
#endif
