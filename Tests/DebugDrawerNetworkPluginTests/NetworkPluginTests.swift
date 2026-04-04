#if DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerNetworkPlugin
    import XCTest

    @MainActor
    final class NetworkPluginTests: XCTestCase {
        func testNetworkEntryCreation() {
            let entry = NetworkEntry(
                timestamp: Date(), method: "GET", url: "https://example.com/api",
                host: "example.com", path: "/api",
                requestHeaders: ["Accept": "application/json"],
                requestBody: nil, isComplete: false
            )
            XCTAssertEqual(entry.method, "GET")
            XCTAssertEqual(entry.host, "example.com")
            XCTAssertFalse(entry.isComplete)
        }

        func testStatusColor() {
            var entry = NetworkEntry(
                timestamp: Date(), method: "GET", url: "", host: "", path: "",
                requestHeaders: [:], requestBody: nil, isComplete: true
            )
            entry.statusCode = 200
            // Can't test Color equality easily, but ensure no crash
            _ = entry.statusColor

            entry.statusCode = 404
            _ = entry.statusColor

            entry.statusCode = 500
            _ = entry.statusColor
        }

        func testResponseSizeLabel() {
            var entry = NetworkEntry(
                timestamp: Date(), method: "GET", url: "", host: "", path: "",
                requestHeaders: [:], requestBody: nil, isComplete: true
            )
            XCTAssertEqual(entry.responseSizeLabel, "—")

            entry.responseBody = Data(repeating: 0, count: 512)
            XCTAssertEqual(entry.responseSizeLabel, "512 B")

            entry.responseBody = Data(repeating: 0, count: 2048)
            XCTAssertEqual(entry.responseSizeLabel, "2 KB")
        }

        func testDurationLabel() {
            var entry = NetworkEntry(
                timestamp: Date(), method: "GET", url: "", host: "", path: "",
                requestHeaders: [:], requestBody: nil, isComplete: true
            )
            XCTAssertEqual(entry.durationLabel, "...")

            entry.duration = 0.050
            XCTAssertEqual(entry.durationLabel, "50ms")

            entry.duration = 1.5
            XCTAssertEqual(entry.durationLabel, "1.50s")
        }

        func testNetworkStoreFilterStatus() {
            let store = NetworkStore.shared
            store.clear()
            XCTAssertEqual(store.filteredEntries.count, 0)
            XCTAssertEqual(store.filterStatus, .all)
        }

        func testPrettyPrintJSON() {
            var entry = NetworkEntry(
                timestamp: Date(), method: "POST", url: "", host: "", path: "",
                requestHeaders: [:], requestBody: nil, isComplete: true
            )
            entry.responseBody = "{\"key\":\"value\"}".data(using: .utf8)
            XCTAssertNotNil(entry.prettyResponseBody)
            XCTAssertTrue(entry.prettyResponseBody!.contains("key"))
        }
    }
#endif
