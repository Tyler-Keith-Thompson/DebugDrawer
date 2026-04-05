#if DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerViewInspectorPlugin
    import XCTest

    @MainActor
    final class ViewInspectorPluginTests: XCTestCase {
        func testViewBorderControllerDefaults() {
            let controller = ViewBorderController.shared
            XCTAssertFalse(controller.isBordersEnabled)
            XCTAssertFalse(controller.isGridEnabled)
            XCTAssertEqual(controller.gridSpacing, 8)
            XCTAssertEqual(controller.animationSpeed, 1.0)
            XCTAssertFalse(controller.isClickIndicatorEnabled)
        }

        func testGridColorCases() {
            for color in ViewBorderController.GridColor.allCases {
                _ = color.color // no crash
            }
        }

        func testRenderTrackerDefaults() {
            let tracker = RenderTracker.shared
            XCTAssertFalse(tracker.isEnabled)
            XCTAssertTrue(tracker.showOverlays)
            XCTAssertEqual(tracker.totalRenders, 0)
        }

        func testRenderTrackerRecord() {
            let tracker = RenderTracker.shared
            tracker.reset()
            tracker.isEnabled = true

            tracker.recordRender("TestView")
            tracker.recordRender("TestView")
            tracker.recordRender("OtherView")

            // Counts are in backing storage (_counts), published values flush async
            XCTAssertEqual(tracker._counts["TestView"], 2)
            XCTAssertEqual(tracker._counts["OtherView"], 1)

            tracker.reset()
            tracker.isEnabled = false
            XCTAssertEqual(tracker._counts.count, 0)
        }

        func testRenderTrackerDisabledSkips() {
            let tracker = RenderTracker.shared
            tracker.reset()
            tracker.isEnabled = false
            tracker.recordRender("ShouldSkip")
            XCTAssertEqual(tracker.totalRenders, 0)
        }

        func testPluginConformance() {
            let plugin = ViewInspectorPlugin()
            XCTAssertEqual(plugin.title, "View Inspector")
            XCTAssertEqual(plugin.icon, "rectangle.dashed")
        }
    }
#endif
