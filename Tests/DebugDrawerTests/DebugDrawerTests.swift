#if DEBUG
    @testable import DebugDrawer
    import SwiftUI
    import XCTest

    struct TestPlugin: DebugDrawerPlugin {
        var title: String
        var icon = "gear"
        var body: some View { Text("test") }
    }

    @MainActor
    final class DebugDrawerTests: XCTestCase {
        override func setUp() {
            // Reset shared state
            let drawer = DebugDrawer.shared
            for plugin in drawer.globalPlugins {
                drawer.unregisterGlobal(id: plugin.id)
            }
        }

        func testRegisterGlobalPlugin() {
            let drawer = DebugDrawer.shared
            XCTAssertEqual(drawer.globalPlugins.count, 0)

            drawer.registerGlobal(TestPlugin(title: "A"))
            XCTAssertEqual(drawer.globalPlugins.count, 1)
            XCTAssertEqual(drawer.globalPlugins[0].title, "A")
        }

        func testDuplicateGlobalIgnored() {
            let drawer = DebugDrawer.shared
            drawer.registerGlobal(TestPlugin(title: "A"))
            drawer.registerGlobal(TestPlugin(title: "A")) // same ID (type name)
            XCTAssertEqual(drawer.globalPlugins.count, 1)
        }

        func testUnregisterGlobal() {
            let drawer = DebugDrawer.shared
            drawer.registerGlobal(TestPlugin(title: "A"))
            drawer.unregisterGlobal(id: "TestPlugin")
            XCTAssertEqual(drawer.globalPlugins.count, 0)
        }

        func testLocalPluginToken() {
            let drawer = DebugDrawer.shared
            let token = drawer.registerLocal(TestPlugin(title: "Local"))
            XCTAssertEqual(drawer.localPlugins.count, 1)

            // Unregister with correct token
            drawer.unregisterLocal(id: "TestPlugin", token: token)
            XCTAssertEqual(drawer.localPlugins.count, 0)
        }

        func testStaleTokenNoOp() {
            let drawer = DebugDrawer.shared
            let oldToken = drawer.registerLocal(TestPlugin(title: "Local"))
            let newToken = drawer.registerLocal(TestPlugin(title: "Updated"))

            // Old token should not remove the new registration
            drawer.unregisterLocal(id: "TestPlugin", token: oldToken)
            XCTAssertEqual(drawer.localPlugins.count, 1)

            // New token should work
            drawer.unregisterLocal(id: "TestPlugin", token: newToken)
            XCTAssertEqual(drawer.localPlugins.count, 0)
        }

        func testHasPlugins() {
            let drawer = DebugDrawer.shared
            XCTAssertFalse(drawer.hasPlugins)

            drawer.registerGlobal(TestPlugin(title: "A"))
            XCTAssertTrue(drawer.hasPlugins)
        }

        func testToggle() {
            let drawer = DebugDrawer.shared
            XCTAssertFalse(drawer.isOpen)
            drawer.toggle()
            XCTAssertTrue(drawer.isOpen)
            drawer.toggle()
            XCTAssertFalse(drawer.isOpen)
        }
    }
#endif
