#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerNetworkPlugin
    import Foundation
    import Testing

    @Suite
    struct NetworkWebSocketArchiveTests {
        @Test("A connection is exported as Chrome DevTools writes one: a GET answered 101, of type websocket, its messages in order with JSON masked")
        func exportsConnection() throws {
            let start = Date(timeIntervalSince1970: 1_800_000_000)
            var connection = NetworkWebSocketConnection(url: "wss://chat.example.com/room?token=secret", protocols: ["chat"], opened: start)
            connection.record(
                NetworkWebSocketFrame(direction: .sent, kind: .text, payload: Data(#"{"password":"hunter2"}"#.utf8), timestamp: start + 1),
                capacity: 10
            )
            connection.record(NetworkWebSocketFrame(direction: .sent, kind: .ping, timestamp: start + 1.5), capacity: 10)
            connection.record(
                NetworkWebSocketFrame(direction: .received, kind: .binary, payload: Data([1, 2, 3]), timestamp: start + 2),
                capacity: 10
            )
            connection.end(.closed(NetworkWebSocketClose(side: .server, code: 1000, reason: "bye", timestamp: start + 3)))
            let request = NetworkEntry(
                timestamp: start + 0.5, method: "GET", url: "https://api.example.com/v1/greeting", host: "api.example.com",
                path: "/v1/greeting", requestHeaders: [:], requestBody: nil, statusCode: 200, duration: 0.1, isComplete: true
            )
            let sut = NetworkArchiveFile(entries: [request], redaction: .standard, webSockets: [connection])

            let actual = sut.data

            let har = try #require(try JSONSerialization.jsonObject(with: actual) as? [String: Any])
            let log = try #require(har["log"] as? [String: Any])
            let entries = try #require(log["entries"] as? [[String: Any]])
            try #require(entries.count == 2)
            let socket = entries[0]
            let socketRequest = try #require(socket["request"] as? [String: Any])
            let socketResponse = try #require(socket["response"] as? [String: Any])
            let messages = try #require(socket["_webSocketMessages"] as? [[String: Any]])
            #expect(socket["_resourceType"] as? String == "websocket")
            #expect(socket["startedDateTime"] as? String == "2027-01-15T08:00:00.000Z")
            #expect(socket["time"] as? Double == 3000)
            #expect(socket["comment"] as? String == "Closed by the server: 1000 Normal closure, “bye”")
            #expect(socketRequest["method"] as? String == "GET")
            #expect(socketRequest["url"] as? String == "wss://chat.example.com/room?token=%5BREDACTED%5D")
            #expect(socketResponse["status"] as? Int == 101)
            #expect(messages.map { $0["type"] as? String } == ["send", "receive"])
            #expect(messages.map { $0["opcode"] as? Int } == [1, 2])
            #expect(messages.map { $0["data"] as? String } == [#"{"password":"[REDACTED]"}"#, "AQID"])
            #expect(messages.map { $0["time"] as? Double } == [1_800_000_001, 1_800_000_002])
            #expect(entries[1]["_resourceType"] == nil)
            #expect(entries[1]["_webSocketMessages"] == nil)
        }

        @Test("A connection that failed before any frame is exported with no answer and its error")
        func exportsFailedConnection() throws {
            let start = Date(timeIntervalSince1970: 1_800_000_000)
            var connection = NetworkWebSocketConnection(url: "wss://chat.example.com/room", opened: start)
            connection.end(.failed(message: "Could not connect to the server.", at: start + 0.25))
            let sut = NetworkArchiveFile(entries: [], redaction: .standard, webSockets: [connection])

            let actual = sut.data

            let har = try #require(try JSONSerialization.jsonObject(with: actual) as? [String: Any])
            let log = try #require(har["log"] as? [String: Any])
            let entry = try #require((log["entries"] as? [[String: Any]])?.first)
            let response = try #require(entry["response"] as? [String: Any])
            #expect(response["status"] as? Int == 0)
            #expect(entry["_error"] as? String == "Could not connect to the server.")
            #expect(entry["time"] as? Double == 250)
            #expect((entry["_webSocketMessages"] as? [Any])?.isEmpty == true)
            #expect(!sut.isEmpty)
        }

        @Test("The bug report's network.har holds the WebSocket connections, even with no request captured")
        func reportHoldsConnections() throws {
            let connection = NetworkWebSocketConnection(url: "wss://chat.example.com/room", opened: Date(timeIntervalSince1970: 1_800_000_000))
            var report = DebugDrawerReport()

            NetworkPlugin.contribute([], webSockets: [connection], to: &report, redaction: .standard)

            let file = try #require(report.files.first)
            let har = try #require(try JSONSerialization.jsonObject(with: file.data) as? [String: Any])
            let log = try #require(har["log"] as? [String: Any])
            let entries = try #require(log["entries"] as? [[String: Any]])
            #expect(file.name == "network.har")
            #expect(entries.map { $0["_resourceType"] as? String } == ["websocket"])
        }

        @Test("An exported connection reads back from the file")
        func roundTrip() throws {
            let start = Date(timeIntervalSince1970: 1_800_000_000)
            var connection = NetworkWebSocketConnection(url: "wss://chat.example.com/room", opened: start)
            connection.record(NetworkWebSocketFrame(direction: .sent, kind: .text, payload: Data("hi".utf8), timestamp: start + 1), capacity: 10)
            let file = NetworkArchiveFile(entries: [], redaction: .standard, webSockets: [connection])
            let expected = [HTTPArchive.WebSocketMessage(type: "send", time: 1_800_000_001, opcode: 1, data: "hi")]

            let actual = try HTTPArchive.read(file.data)

            #expect(actual.log.entries.first?.resourceType == "websocket")
            #expect(actual.log.entries.first?.webSocketMessages == expected)
        }
    }
#endif
