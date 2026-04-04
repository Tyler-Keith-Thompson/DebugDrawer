#if DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerDiskIOPlugin
    import XCTest

    @MainActor
    final class DiskIOPluginTests: XCTestCase {
        func testIOEventCreation() {
            let event = IOEvent(
                timestamp: Date(), operation: .read, path: "/tmp/test.txt",
                size: 1024, duration: 0.005, isMainThread: true
            )
            XCTAssertEqual(event.operation, .read)
            XCTAssertEqual(event.size, 1024)
            XCTAssertTrue(event.isMainThread)
        }

        func testIOOperationColors() {
            // Ensure each operation has a distinct color (no crashes)
            for op in [IOEvent.Operation.read, .write, .delete, .create, .list, .stat] {
                _ = op.color
            }
        }

        func testDiskIOStoreFilter() {
            let store = DiskIOStore.shared
            store.clear()
            XCTAssertEqual(store.filteredEvents.count, 0)

            store.filterOp = .read
            XCTAssertEqual(store.filteredEvents.count, 0)

            store.filterOp = nil
            store.mainThreadOnly = true
            XCTAssertEqual(store.filteredEvents.count, 0)
            store.mainThreadOnly = false
        }

        func testDiskIOStoreStats() {
            let store = DiskIOStore.shared
            store.clear()
            XCTAssertEqual(store.totalReads, 0)
            XCTAssertEqual(store.totalWrites, 0)
            XCTAssertEqual(store.totalBytesRead, 0)
            XCTAssertEqual(store.totalBytesWritten, 0)
            XCTAssertEqual(store.mainThreadOps, 0)
        }

        func testPluginConformance() {
            let plugin = DiskIOPlugin()
            XCTAssertEqual(plugin.title, "Disk I/O")
            XCTAssertEqual(plugin.icon, "externaldrive")
        }
    }
#endif
