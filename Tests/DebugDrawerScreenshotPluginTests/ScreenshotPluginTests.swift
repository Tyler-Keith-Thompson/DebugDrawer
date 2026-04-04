#if DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerScreenshotPlugin
    import XCTest

    @MainActor
    final class ScreenshotPluginTests: XCTestCase {
        func testPluginConformance() {
            let plugin = ScreenshotPlugin()
            XCTAssertEqual(plugin.title, "Screenshot")
            XCTAssertEqual(plugin.icon, "camera")
        }
    }
#endif
