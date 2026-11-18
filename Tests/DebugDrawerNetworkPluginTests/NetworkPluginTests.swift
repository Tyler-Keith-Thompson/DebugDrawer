#if DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerNetworkPlugin
    import Foundation
    import Testing

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct NetworkPluginTests {
        @Test("An entry keeps the method and host it was made with, and starts incomplete")
        func networkEntryCreation() {
            let entry = NetworkEntry(
                timestamp: Date(), method: "GET", url: "https://example.com/api",
                host: "example.com", path: "/api",
                requestHeaders: ["Accept": "application/json"],
                requestBody: nil, isComplete: false
            )
            #expect(entry.method == "GET")
            #expect(entry.host == "example.com")
            #expect(!entry.isComplete)
        }

        @Test("The response size label is a dash with no body, then bytes, then kilobytes")
        func responseSizeLabel() {
            var entry = NetworkEntry(
                timestamp: Date(), method: "GET", url: "", host: "", path: "",
                requestHeaders: [:], requestBody: nil, isComplete: true
            )
            #expect(entry.responseSizeLabel == "—")

            entry.responseBody = Data(repeating: 0, count: 512)
            #expect(entry.responseSizeLabel == "512 B")

            entry.responseBody = Data(repeating: 0, count: 2048)
            #expect(entry.responseSizeLabel == "2 KB")
        }

        @Test("The duration label is an ellipsis with no duration, milliseconds under a second, and seconds above")
        func durationLabel() {
            var entry = NetworkEntry(
                timestamp: Date(), method: "GET", url: "", host: "", path: "",
                requestHeaders: [:], requestBody: nil, isComplete: true
            )
            #expect(entry.durationLabel == "...")

            entry.duration = 0.050
            #expect(entry.durationLabel == "50ms")

            entry.duration = 1.5
            #expect(entry.durationLabel == "1.50s")
        }

        // A store of its own: clearing the shared one would drop the requests the interception
        // suites are waiting to see logged.
        @Test("A cleared store shows no entries, and its status filter starts at All")
        func networkStoreFilterStatus() {
            let store = NetworkStore(ignoreStorage: FakeNetworkIgnoreListStorage())
            store.clear()
            #expect(store.filteredEntries.isEmpty)
            #expect(store.filterStatus == .all)
        }

        @Test("A JSON response body is pretty-printed with its keys")
        func prettyPrintJSON() throws {
            var entry = NetworkEntry(
                timestamp: Date(), method: "POST", url: "", host: "", path: "",
                requestHeaders: [:], requestBody: nil, isComplete: true
            )
            entry.responseBody = Data("{\"key\":\"value\"}".utf8)
            let pretty = try #require(entry.prettyResponseBody)
            #expect(pretty.contains("key"))
        }
    }
#endif
