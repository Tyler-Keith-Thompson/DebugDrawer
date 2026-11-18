#if DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerEnergyPlugin
    import Testing

    @MainActor
    @Suite("Energy plugin")
    struct EnergyPluginTests {
        @Test("start() samples and stop() ends it")
        func startStop() {
            let sut = EnergyMonitor(batteryMonitoring: nil)

            sut.start()
            let monitoringAfterStart = sut.isMonitoring
            sut.stop()

            #expect(monitoringAfterStart)
            #expect(!sut.isMonitoring)
        }

        @Test("The plugin is titled Energy with the bolt icon")
        func conformance() {
            let expectedTitle = "Energy"
            let expectedIcon = "bolt.fill"

            let sut = EnergyPlugin()

            #expect(sut.title == expectedTitle)
            #expect(sut.icon == expectedIcon)
        }
    }
#endif
