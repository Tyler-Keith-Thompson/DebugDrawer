#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerNetworkPlugin
    import Foundation
    import Testing

    @MainActor
    @Suite
    struct NetworkCaptureBoundsTests {
        @Test("Past capacity the oldest request goes, and the log lists the rest newest first")
        func countBound() throws {
            let sut = NetworkStore(ignoreStorage: FakeNetworkIgnoreListStorage())
            try sut.setCapacity(2)
            let paths = ["/a", "/b", "/c"]
            let expected = ["/c", "/b"]

            for path in paths {
                sut.recordStart(NetworkEntry(
                    timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000), method: "GET", url: "https://api.example.com\(path)",
                    host: "api.example.com", path: path, requestHeaders: [:], requestBody: nil, isComplete: false
                ))
            }

            #expect(sut.entries.map(\.path) == expected)
        }

        @Test("Request bodies past byteCapacity drop the oldest requests until the kept bodies fit")
        func requestBodiesBound() throws {
            let sut = NetworkStore(ignoreStorage: FakeNetworkIgnoreListStorage())
            try sut.setByteCapacity(250)
            let expected = ["/c", "/b"]

            for path in ["/a", "/b", "/c"] {
                sut.recordStart(NetworkEntry(
                    timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000), method: "POST", url: "https://api.example.com\(path)",
                    host: "api.example.com", path: path, requestHeaders: [:], requestBody: Data(repeating: 0xFF, count: 100), isComplete: false
                ))
            }

            #expect(sut.entries.map(\.path) == expected)
        }

        @Test("A response body arriving past byteCapacity drops the oldest requests, and the completed one keeps its response")
        func responseBodyBound() throws {
            let sut = NetworkStore(ignoreStorage: FakeNetworkIgnoreListStorage())
            try sut.setByteCapacity(1000)
            var ids: [UUID] = []
            for path in ["/a", "/b", "/c"] {
                let entry = NetworkEntry(
                    timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000), method: "GET", url: "https://api.example.com\(path)",
                    host: "api.example.com", path: path, requestHeaders: [:], requestBody: Data(repeating: 0xFF, count: 300), isComplete: false
                )
                ids.append(entry.id)
                sut.recordStart(entry)
            }
            let body = Data(repeating: 0xFF, count: 200)

            sut.recordCompletion(id: ids[2], NetworkCompletion(statusCode: 200, body: NetworkResponseBody(body)))

            #expect(sut.entries.map(\.path) == ["/c", "/b"])
            #expect(sut.entries.first?.responseBody == body)
            #expect(sut.entries.first?.statusCode == 200)
            #expect(sut.entries.first?.isComplete == true)
        }

        @Test("A completion for a request the log no longer keeps changes nothing")
        func completionOfDroppedRequest() throws {
            let sut = NetworkStore(ignoreStorage: FakeNetworkIgnoreListStorage())
            try sut.setCapacity(1)
            let dropped = NetworkEntry(
                timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000), method: "GET", url: "https://api.example.com/a",
                host: "api.example.com", path: "/a", requestHeaders: [:], requestBody: nil, isComplete: false
            )
            sut.recordStart(dropped)
            sut.recordStart(NetworkEntry(
                timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000), method: "GET", url: "https://api.example.com/b",
                host: "api.example.com", path: "/b", requestHeaders: [:], requestBody: nil, isComplete: false
            ))

            sut.recordCompletion(id: dropped.id, NetworkCompletion(statusCode: 200))

            #expect(sut.entries.map(\.path) == ["/b"])
            #expect(sut.entries.first?.statusCode == nil)
        }

        @Test("Clearing empties the log")
        func clear() {
            // A recorder of its own: clearing the shared one would drop the connections the
            // WebSocket tests, running beside this one, are recording.
            let sut = NetworkStore(
                ignoreStorage: FakeNetworkIgnoreListStorage(),
                webSocketRecorder: NetworkWebSocketRecorder(connectionCapacity: 10, frameCapacity: 10)
            )
            sut.recordStart(NetworkEntry(
                timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000), method: "GET", url: "https://api.example.com/a",
                host: "api.example.com", path: "/a", requestHeaders: [:], requestBody: nil, isComplete: false
            ))

            sut.clear()

            #expect(sut.entries.isEmpty)
        }

        @Test("A negative capacity throws negativeMaxCount and keeps the capacity")
        func negativeCapacity() {
            let sut = NetworkStore(ignoreStorage: FakeNetworkIgnoreListStorage())
            let expected = sut.capacity

            #expect(throws: CaptureBuffer<NetworkEntry>.InvalidLimit.negativeMaxCount) {
                try sut.setCapacity(-1)
            }
            #expect(sut.capacity == expected)
        }

        @Test("A negative byte capacity throws negativeMaxByteCount and keeps the byte capacity")
        func negativeByteCapacity() {
            let sut = NetworkStore(ignoreStorage: FakeNetworkIgnoreListStorage())
            let expected = sut.byteCapacity

            #expect(throws: CaptureBuffer<NetworkEntry>.InvalidLimit.negativeMaxByteCount) {
                try sut.setByteCapacity(-1)
            }
            #expect(sut.byteCapacity == expected)
        }
    }
#endif
