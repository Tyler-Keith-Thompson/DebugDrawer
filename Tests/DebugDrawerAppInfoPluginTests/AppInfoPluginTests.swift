#if DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerAppInfoPlugin
    import XCTest

    @MainActor
    final class AppInfoPluginTests: XCTestCase {
        func testAppMetricsRefresh() {
            let metrics = AppMetrics.shared
            metrics.refresh()
            XCTAssertGreaterThan(metrics.memoryMB, 0)
            XCTAssertGreaterThanOrEqual(metrics.uptime, 0)
        }

        func testPluginConformance() {
            let plugin = AppInfoPlugin()
            XCTAssertEqual(plugin.title, "App Info")
            XCTAssertEqual(plugin.icon, "info.circle")
        }

        func testMachineHardwareName() {
            let name = ProcessInfo.processInfo.machineHardwareName
            XCTAssertFalse(name.isEmpty)
        }
    }
#endif
