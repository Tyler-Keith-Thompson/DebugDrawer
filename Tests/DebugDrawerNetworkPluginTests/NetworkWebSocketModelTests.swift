#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerNetworkPlugin
    import Foundation
    import os
    import Testing

    @Suite
    struct NetworkWebSocketModelTests {
        // MARK: Frame cap

        @Test("A connection keeps its latest frames up to the cap, counting the earliest it let go")
        func frameCap() {
            let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
            var sut = NetworkWebSocketConnection(url: "wss://chat.example.com/room", opened: start)
            let frames = (0 ..< 5).map { index in
                NetworkWebSocketFrame(
                    direction: index.isMultiple(of: 2) ? .sent : .received, kind: .text,
                    payload: Data("message \(index)".utf8), timestamp: start + Double(index)
                )
            }

            for frame in frames {
                sut.record(frame, capacity: 3)
            }

            #expect(sut.frames.map(\.text) == ["message 4", "message 3", "message 2"])
            #expect(sut.droppedFrames == 2)
            #expect(sut.frameCount == 5)
            #expect(sut.sentFrames == 3)
            #expect(sut.receivedFrames == 2)
        }

        @Test("A cap of one keeps the latest frame; a cap of zero keeps none and counts them all")
        func frameCapBoundaries() {
            let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
            var one = NetworkWebSocketConnection(url: "wss://chat.example.com/room", opened: start)
            var none = NetworkWebSocketConnection(url: "wss://chat.example.com/room", opened: start)
            let first = NetworkWebSocketFrame(direction: .sent, kind: .text, payload: Data("a".utf8), timestamp: start)
            let second = NetworkWebSocketFrame(direction: .received, kind: .text, payload: Data("b".utf8), timestamp: start + 1)

            for frame in [first, second] {
                one.record(frame, capacity: 1)
                none.record(frame, capacity: 0)
            }

            #expect(one.frames == [second])
            #expect(one.droppedFrames == 1)
            #expect(none.frames.isEmpty)
            #expect(none.droppedFrames == 2)
            #expect(none.frameCount == 2)
        }

        @Test("The recorder keeps its latest connections up to its cap, and each one's frames up to the frame cap")
        func recorderCaps() {
            let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
            let sut = NetworkWebSocketRecorder(connectionCapacity: 2, frameCapacity: 2)
            let connections = (0 ..< 3).map { NetworkWebSocketConnection(url: "wss://example.com/\($0)", opened: start + Double($0)) }
            for connection in connections {
                sut.open(connection)
            }
            let latest = connections[2].id

            for index in 0 ..< 4 {
                sut.record(NetworkWebSocketFrame(direction: .sent, kind: .binary, payload: Data([UInt8(index)]), timestamp: start), on: latest)
            }
            sut.record(NetworkWebSocketFrame(direction: .sent, kind: .ping, timestamp: start), on: connections[0].id)

            let actual = sut.connections
            #expect(actual.map(\.url) == ["wss://example.com/2", "wss://example.com/1"])
            #expect(actual.first?.frames.map(\.payload) == [Data([3]), Data([2])])
            #expect(actual.first?.droppedFrames == 2)
        }

        @Test("A connection ends once: what follows the first end changes nothing")
        func endsOnce() {
            let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
            let sut = NetworkWebSocketRecorder(connectionCapacity: 5, frameCapacity: 5)
            let connection = NetworkWebSocketConnection(url: "wss://example.com/", opened: start)
            sut.open(connection)
            let close = NetworkWebSocketClose(side: .app, code: 1000, reason: nil, timestamp: start + 1)

            sut.end(connection.id, .closed(close))
            sut.end(connection.id, .failed(message: "cancelled", at: start + 2))

            #expect(sut.connections.first?.state == .closed(close))
        }

        @Test("Each change to the recorder is reported; a change to a connection it no longer keeps is not")
        func reportsChanges() {
            let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
            let changes = OSAllocatedUnfairLock(initialState: 0)
            let sut = NetworkWebSocketRecorder(connectionCapacity: 5, frameCapacity: 5) { changes.withLock { $0 += 1 } }
            let connection = NetworkWebSocketConnection(url: "wss://example.com/", opened: start)

            sut.open(connection)
            sut.record(NetworkWebSocketFrame(direction: .sent, kind: .ping, timestamp: start), on: connection.id)
            sut.record(NetworkWebSocketFrame(direction: .sent, kind: .ping, timestamp: start), on: UUID())
            sut.clear()
            sut.record(NetworkWebSocketFrame(direction: .sent, kind: .ping, timestamp: start), on: connection.id)

            #expect(changes.withLock { $0 } == 3)
            #expect(sut.connections.isEmpty)
        }

        // MARK: Previews

        @Test("The hex preview shows up to 16 bytes as lowercase pairs, with an ellipsis only when there are more", arguments: [
            (Data(), ""),
            (Data([0xAB]), "ab"),
            (Data(0 ..< 16), "00 01 02 03 04 05 06 07 08 09 0a 0b 0c 0d 0e 0f"),
            (Data(0 ..< 17), "00 01 02 03 04 05 06 07 08 09 0a 0b 0c 0d 0e 0f …")
        ])
        func hexPreview(payload: Data, expected: String) {
            let sut = NetworkWebSocketFrame(direction: .received, kind: .binary, payload: payload, timestamp: .distantPast)

            let actual = sut.hexPreview

            #expect(actual == expected)
        }

        @Test("A text preview flattens line breaks and stops at 200 characters with an ellipsis")
        func textPreview() {
            let long = String(repeating: "a", count: 201)
            let exact = String(repeating: "b", count: 200)

            let flattened = NetworkWebSocketFrame.textPreview("{\n  \"a\": 1\n}")
            let truncated = NetworkWebSocketFrame.textPreview(long)
            let whole = NetworkWebSocketFrame.textPreview(exact)
            let notKept = NetworkWebSocketFrame.textPreview("abc", isWhole: false)

            #expect(flattened == "{ \"a\": 1 }")
            #expect(truncated == String(repeating: "a", count: 200) + "…")
            #expect(whole == exact)
            #expect(notKept == "abc…")
        }

        @Test("A frame keeps the first 16 KB of a larger payload and its whole size")
        func keptBytes() {
            let payload = Data(repeating: 7, count: NetworkWebSocketFrame.keptBytes + 1)
            let text = String(repeating: "x", count: NetworkWebSocketFrame.keptBytes + 1)

            let binary = NetworkWebSocketFrame(direction: .sent, kind: .binary, payload: payload, timestamp: .distantPast)
            let message = NetworkWebSocketFrame(__NSURLSessionWebSocketMessage(string: text), direction: .sent, timestamp: .distantPast)

            #expect(binary.size == NetworkWebSocketFrame.keptBytes + 1)
            #expect(binary.payload.count == NetworkWebSocketFrame.keptBytes)
            #expect(!binary.isWhole)
            #expect(message.kind == .text)
            #expect(message.size == NetworkWebSocketFrame.keptBytes + 1)
            #expect(message.payload.count == NetworkWebSocketFrame.keptBytes)
            #expect(message.sizeLabel == "16 KB")
        }

        @Test("Close codes read with their RFC 6455 names; private codes as numbers; none as None", arguments: [
            (1000, "1000 Normal closure"),
            (1001, "1001 Going away"),
            (1011, "1011 Internal server error"),
            (4000, "4000"),
            (0, "None")
        ])
        func closeCodeLabel(code: Int, expected: String) {
            let sut = NetworkWebSocketClose(side: .server, code: code, reason: nil, timestamp: .distantPast)

            let actual = sut.codeLabel

            #expect(actual == expected)
        }

        @Test("A close reason is read as UTF-8, as hex when it isn't, and is nil when empty")
        func closeReason() {
            let text = NetworkWebSocketClose.reason(Data("bye".utf8))
            let bytes = NetworkWebSocketClose.reason(Data([0xFF, 0xFE]))
            let empty = NetworkWebSocketClose.reason(Data())
            let none = NetworkWebSocketClose.reason(nil)

            #expect(text == "bye")
            #expect(bytes == "ff fe")
            #expect(empty == nil)
            #expect(none == nil)
        }

        // MARK: Filter

        @Test("All lists every connection, Errors the failed ones, and the HTTP status filters none")
        func statusFilter() {
            let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
            let open = NetworkWebSocketConnection(url: "wss://example.com/open", opened: start)
            var failed = NetworkWebSocketConnection(url: "wss://example.com/failed", opened: start)
            failed.end(.failed(message: "The network connection was lost.", at: start))
            let connections = [open, failed]

            let all = NetworkStore.connections(connections, matching: .all, text: "")
            let errors = NetworkStore.connections(connections, matching: .errors, text: "")
            let success = NetworkStore.connections(connections, matching: .success, text: "")

            #expect(all.map(\.url) == ["wss://example.com/open", "wss://example.com/failed"])
            #expect(errors.map(\.url) == ["wss://example.com/failed"])
            #expect(success.isEmpty)
        }

        @Test("The filter text matches a connection's URL, its WS method or the text of a frame, ignoring case")
        func textFilter() {
            let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
            var chat = NetworkWebSocketConnection(url: "wss://example.com/chat", opened: start)
            chat.record(NetworkWebSocketFrame(direction: .received, kind: .text, payload: Data("Hello there".utf8), timestamp: start), capacity: 10)
            let prices = NetworkWebSocketConnection(url: "wss://example.com/prices", opened: start)
            let connections = [chat, prices]

            let byURL = NetworkStore.connections(connections, matching: .all, text: "PRICES")
            let byFrame = NetworkStore.connections(connections, matching: .all, text: "hello")
            let byMethod = NetworkStore.connections(connections, matching: .all, text: "ws")
            let byNothing = NetworkStore.connections(connections, matching: .all, text: "orders")

            #expect(byURL.map(\.url) == ["wss://example.com/prices"])
            #expect(byFrame.map(\.url) == ["wss://example.com/chat"])
            #expect(byMethod.count == 2)
            #expect(byNothing.isEmpty)
        }

        // MARK: Copy

        @Test("Copy Frames lists the connection and its frames, the earliest first, with sensitive values masked")
        func transcript() {
            let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
            var sut = NetworkWebSocketConnection(url: "wss://chat.example.com/room?token=secret", protocols: ["chat"], opened: start)
            sut.record(
                NetworkWebSocketFrame(
                    direction: .sent, kind: .text, payload: Data(#"{"password":"hunter2","text":"hi"}"#.utf8), timestamp: start + 0.125
                ),
                capacity: 10
            )
            sut.record(NetworkWebSocketFrame(direction: .received, kind: .binary, payload: Data([1, 2, 3]), timestamp: start + 0.25), capacity: 10)
            sut.record(
                NetworkWebSocketFrame(direction: .sent, kind: .ping, timestamp: start + 0.5).failed("The network connection was lost."),
                capacity: 10
            )
            sut.end(.closed(NetworkWebSocketClose(side: .server, code: 1000, reason: "bye", timestamp: start + 1)))
            let expected = """
            WebSocket wss://chat.example.com/room?token=%5BREDACTED%5D
            Opened 06:13:20.000
            Protocols chat
            Closed by the server at 06:13:21.000: 1000 Normal closure, "bye"
            ↑ 06:13:20.125 Text · 34 B: {"password":"[REDACTED]","text":"hi"}
            ↓ 06:13:20.250 Binary · 3 B: 01 02 03
            ↑ 06:13:20.500 Ping (no pong: The network connection was lost.)
            """

            let actual = sut.transcript(redaction: .standard, timeZone: TimeZone(identifier: "UTC") ?? .gmt)

            #expect(actual == expected)
        }

        @Test("A text frame larger than what a frame keeps is copied without its text, which can't be masked")
        func transcriptOfLargeText() {
            let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
            var sut = NetworkWebSocketConnection(url: "wss://chat.example.com/room", opened: start)
            let large = Data(("{\"token\":\"" + String(repeating: "x", count: NetworkWebSocketFrame.keptBytes) + "\"}").utf8)
            sut.record(NetworkWebSocketFrame(direction: .received, kind: .text, payload: large, timestamp: start), capacity: 10)

            let actual = sut.transcript(redaction: .standard, timeZone: TimeZone(identifier: "UTC") ?? .gmt)

            #expect(actual.hasSuffix("↓ 06:13:20.000 Text · 16 KB: (larger than 16 KB, not kept)"))
            #expect(!actual.contains("xxxx"))
        }
    }
#endif
