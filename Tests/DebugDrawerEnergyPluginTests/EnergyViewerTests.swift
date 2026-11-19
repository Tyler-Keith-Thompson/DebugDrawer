#if DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerEnergyPlugin
    import Testing

    /// Stands in for the 1 s timer: records starts and stops, and ticks when the test says.
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
    }

    @MainActor
    @Suite("Energy sampling")
    struct EnergyViewerTests {
        @Test("Nothing samples until the view shows")
        func idleUntilShown() {
            let timer = FakeSamplingTimer()

            let sut = EnergyMonitor(batteryMonitoring: nil, timer: timer)

            #expect(timer.starts == 0)
            #expect(!sut.isMonitoring)
        }

        @Test("Sampling starts on the first viewer and stops after the last one leaves")
        func referenceCounted() {
            let timer = FakeSamplingTimer()
            let sut = EnergyMonitor(batteryMonitoring: nil, timer: timer)

            sut.addViewer()
            sut.addViewer()
            sut.removeViewer()
            let startsWhileOneViewerRemains = timer.starts
            let runningWhileOneViewerRemains = timer.isRunning
            sut.removeViewer()

            #expect(startsWhileOneViewerRemains == 1)
            #expect(runningWhileOneViewerRemains)
            #expect(timer.stops == 1)
            #expect(!timer.isRunning)
            #expect(!sut.isMonitoring)
        }

        @Test("The app's start() keeps sampling after the view goes, until its stop()")
        func appDemand() {
            let timer = FakeSamplingTimer()
            let sut = EnergyMonitor(batteryMonitoring: nil, timer: timer)

            sut.start()
            sut.addViewer()
            sut.removeViewer()
            let runningAfterTheViewWent = timer.isRunning
            sut.stop()

            #expect(runningAfterTheViewWent)
            #expect(timer.starts == 1)
            #expect(timer.stops == 1)
            #expect(!sut.isMonitoring)
        }

        @Test("Installing the plugin samples nothing until its view shows")
        func installStartsNothing() {
            let sut = DebugDrawer.shared

            sut.installEnergy()

            #expect(!EnergyMonitor.shared.isMonitoring)
        }
    }
#endif
