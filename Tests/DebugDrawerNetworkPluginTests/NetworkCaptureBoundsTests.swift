#if DEBUG
    @testable import DebugDrawerNetworkPlugin
    import Foundation
    import Testing

    @MainActor
    @Suite
    struct NetworkCaptureBoundsTests {
        @Test("Past capacity the oldest request goes, and the log lists the rest newest first")
        func countBound() {
            let sut = NetworkStore(ignoreStorage: FakeNetworkIgnoreListStorage())
            sut.capacity = 2
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
        func requestBodiesBound() {
            let sut = NetworkStore(ignoreStorage: FakeNetworkIgnoreListStorage())
            sut.byteCapacity = 250
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
        func responseBodyBound() {
            let sut = NetworkStore(ignoreStorage: FakeNetworkIgnoreListStorage())
            sut.byteCapacity = 1000
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
        func completionOfDroppedRequest() {
            let sut = NetworkStore(ignoreStorage: FakeNetworkIgnoreListStorage())
            sut.capacity = 1
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
            let sut = NetworkStore(ignoreStorage: FakeNetworkIgnoreListStorage())
            sut.recordStart(NetworkEntry(
                timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000), method: "GET", url: "https://api.example.com/a",
                host: "api.example.com", path: "/a", requestHeaders: [:], requestBody: nil, isComplete: false
            ))

            sut.clear()

            #expect(sut.entries.isEmpty)
        }
    }
#endif
