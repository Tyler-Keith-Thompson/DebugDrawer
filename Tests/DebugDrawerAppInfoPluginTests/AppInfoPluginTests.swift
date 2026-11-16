#if DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerAppInfoPlugin
    import XCTest

    @MainActor
    final class AppInfoPluginTests: XCTestCase {
        func testAppMetricsRefresh() {
            let metrics = AppMetrics.shared
            metrics.refresh()
            XCTAssertGreaterThan(metrics.footprintMB, 0)
            XCTAssertGreaterThan(try XCTUnwrap(metrics.uptime), 0)
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
