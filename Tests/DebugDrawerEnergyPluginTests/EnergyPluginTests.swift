#if DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerEnergyPlugin
    import XCTest

    @MainActor
    final class EnergyPluginTests: XCTestCase {
        func testMonitorStartStop() {
            let monitor = EnergyMonitor.shared
            monitor.stop()
            XCTAssertFalse(monitor.isMonitoring)
            monitor.start()
            XCTAssertTrue(monitor.isMonitoring)
            monitor.stop()
            XCTAssertFalse(monitor.isMonitoring)
        }

        func testThermalLabels() {
            let monitor = EnergyMonitor.shared
            // Just ensure the computed properties don't crash
            _ = monitor.thermalLabel
            _ = monitor.thermalColor
            _ = monitor.energyImpact
            _ = monitor.energyImpactColor
        }

        func testPluginConformance() {
            let plugin = EnergyPlugin()
            XCTAssertEqual(plugin.title, "Energy")
            XCTAssertEqual(plugin.icon, "bolt.fill")
        }
    }
#endif
