#if DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerFileBrowserPlugin
    import XCTest

    @MainActor
    final class FileBrowserPluginTests: XCTestCase {
        func testFSNodeScan() {
            let tmp = NSTemporaryDirectory()
            let node = FSNode.scan(at: tmp, maxDepth: 1)
            XCTAssertTrue(node.isDirectory)
            XCTAssertFalse(node.name.isEmpty)
        }

        func testFSNodeSizeLabel() {
            let small = FSNode.scan(at: "/dev/null", maxDepth: 0)
            // /dev/null is a file with 0 size
            XCTAssertFalse(small.isDirectory)
        }

        func testPluginConformance() {
            let plugin = FileBrowserPlugin()
            XCTAssertEqual(plugin.title, "File Browser")
            XCTAssertEqual(plugin.icon, "folder")
        }
    }
#endif
