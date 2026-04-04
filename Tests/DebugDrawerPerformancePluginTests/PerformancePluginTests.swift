#if DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerPerformancePlugin
    import XCTest

    @MainActor
    final class PerformancePluginTests: XCTestCase {
        func testMonitorStartStop() {
            let monitor = PerformanceMonitor.shared
            XCTAssertFalse(monitor.isMonitoring)
            monitor.start()
            XCTAssertTrue(monitor.isMonitoring)
            monitor.stop()
            XCTAssertFalse(monitor.isMonitoring)
        }

        func testMonitorInitialValues() {
            let monitor = PerformanceMonitor.shared
            monitor.stop()
            // FPS and memory should have been sampled if previously started
            // Just verify no crash on access
            _ = monitor.fps
            _ = monitor.memoryMB
        }

        func testPluginConformance() {
            let plugin = PerformancePlugin()
            XCTAssertEqual(plugin.title, "Performance")
            XCTAssertFalse(plugin.id.isEmpty)
        }
    }
#endif
