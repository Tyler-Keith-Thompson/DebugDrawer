// ViewInspector is linked on Apple platforms only, and the views are tested on the Mac.
#if os(macOS)
    @testable import DebugDrawer
    @testable import DebugDrawerNetworkPlugin
    import Foundation
    import SwiftUI
    import Testing
    import ViewInspector

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct NetworkWebSocketViewTests {
        @Test("A connection's row shows WS, whether it is open, its path and how many frames it carried")
        func row() throws {
            let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
            var connection = NetworkWebSocketConnection(url: "wss://chat.example.com/v1/room", opened: start)
            connection.record(NetworkWebSocketFrame(direction: .sent, kind: .text, payload: Data("hi".utf8), timestamp: start), capacity: 10)
            connection.record(NetworkWebSocketFrame(direction: .received, kind: .text, payload: Data("hi".utf8), timestamp: start), capacity: 10)
            let sut = NetworkWebSocketRow(connection: connection, redaction: .standard, isSelected: false, onSelect: {})

            let view = try sut.inspect()

            #expect(throws: Never.self) { try view.find(text: "WS") }
            #expect(throws: Never.self) { try view.find(text: "Open") }
            #expect(throws: Never.self) { try view.find(text: "/v1/room") }
            #expect(throws: Never.self) { try view.find(text: "2 frames") }
            #expect((try? view.find(NetworkWebSocketDetail.self)) == nil)
        }

        @Test("Choosing a connection's row selects it")
        func rowSelects() throws {
            let connection = NetworkWebSocketConnection(url: "wss://chat.example.com/v1/room", opened: .distantPast)
            var selected = 0
            let sut = NetworkWebSocketRow(connection: connection, redaction: .standard, isSelected: false, onSelect: { selected += 1 })

            try sut.inspect().find(button: "WS").tap()

            #expect(selected == 1)
        }

        @Test("A selected row shows the detail: frames with their arrows, times, sizes and previews, and the close's code and reason")
        func detail() throws {
            let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
            var connection = NetworkWebSocketConnection(url: "wss://chat.example.com/v1/room", opened: start)
            connection.record(
                NetworkWebSocketFrame(direction: .sent, kind: .text, payload: Data("hello".utf8), timestamp: start + 0.125),
                capacity: 10
            )
            connection.record(
                NetworkWebSocketFrame(direction: .received, kind: .binary, payload: Data(0 ..< 20), timestamp: start + 0.25),
                capacity: 10
            )
            connection.end(.closed(NetworkWebSocketClose(side: .server, code: 1000, reason: "bye", timestamp: start + 1)))
            let sut = NetworkWebSocketRow(connection: connection, redaction: .standard, isSelected: true, onSelect: {})
                .environment(\.timeZone, TimeZone(identifier: "UTC") ?? .gmt)

            let view = try sut.inspect()

            #expect(throws: Never.self) { try view.find(text: "Closed") }
            #expect(throws: Never.self) { try view.find(text: "↑") }
            #expect(throws: Never.self) { try view.find(text: "↓") }
            #expect(throws: Never.self) { try view.find(text: "06:13:20.125") }
            #expect(throws: Never.self) { try view.find(text: "06:13:20.250") }
            #expect(throws: Never.self) { try view.find(text: "Text · 5 B") }
            #expect(throws: Never.self) { try view.find(text: "hello") }
            #expect(throws: Never.self) { try view.find(text: "Binary · 20 B") }
            #expect(throws: Never.self) { try view.find(text: "00 01 02 03 04 05 06 07 08 09 0a 0b 0c 0d 0e 0f …") }
            #expect(throws: Never.self) { try view.find(text: "The server") }
            #expect(throws: Never.self) { try view.find(text: "1000 Normal closure") }
            #expect(throws: Never.self) { try view.find(text: "bye") }
            #expect(throws: Never.self) { try view.find(button: "Copy Frames") }
        }

        @Test("A connection that failed says so, with the error")
        func failed() throws {
            var connection = NetworkWebSocketConnection(url: "wss://chat.example.com/v1/room", opened: .distantPast)
            connection.end(.failed(message: "The network connection was lost.", at: .distantPast))
            let sut = NetworkWebSocketRow(connection: connection, redaction: .standard, isSelected: true, onSelect: {})

            let view = try sut.inspect()

            #expect(throws: Never.self) { try view.find(text: "Failed") }
            #expect(throws: Never.self) { try view.find(text: "Connection failed") }
            #expect(throws: Never.self) { try view.find(text: "The network connection was lost.") }
        }

        @Test("A JSON text frame's sensitive values are masked until revealed")
        func masksJSON() throws {
            let frame = NetworkWebSocketFrame(direction: .sent, kind: .text, payload: Data(#"{"token":"abc"}"#.utf8), timestamp: .distantPast)
            let sut = NetworkWebSocketFrameRow(frame: frame, redaction: .standard)

            let view = try sut.inspect()

            #expect(throws: Never.self) { try view.find(text: #"{"token":"[REDACTED]"}"#) }
            #expect((try? view.find(text: #"{"token":"abc"}"#)) == nil)
            let reveal = try? view.find(ViewType.Button.self) { try $0.accessibilityLabel().string() == "Reveal value" }
            #expect(reveal != nil)
        }

        @Test("The detail lists the latest 50 frames until Show All lists every one")
        func showAll() async throws {
            let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
            var connection = NetworkWebSocketConnection(url: "wss://chat.example.com/v1/room", opened: start)
            for index in 0 ..< 60 {
                connection.record(
                    NetworkWebSocketFrame(direction: .received, kind: .text, payload: Data("message \(index)".utf8), timestamp: start),
                    capacity: 500
                )
            }
            let sut = NetworkWebSocketDetail(connection: connection, redaction: .standard)
            var rowsBefore = 0
            var rowsAfter = 0
            var earliestAfter = false

            try await ViewHosting.host(sut) {
                try await sut.inspection.inspect { view in
                    rowsBefore = view.findAll(NetworkWebSocketFrameRow.self).count
                    try view.find(button: "Show All 60").tap()
                }
                try await sut.inspection.inspect { view in
                    rowsAfter = view.findAll(NetworkWebSocketFrameRow.self).count
                    earliestAfter = (try? view.find(text: "message 0")) != nil
                }
            }

            #expect(rowsBefore == 50)
            #expect(rowsAfter == 60)
            #expect(earliestAfter)
        }

        @Test("The WebSockets section lists each connection, and shows nothing while there are none")
        func section() throws {
            let connections = ["/a", "/b"].map { NetworkWebSocketConnection(url: "wss://chat.example.com\($0)", opened: .distantPast) }
            let filled = NetworkWebSocketsSection(connections: connections, redaction: .standard, selected: .constant(nil))
            let empty = NetworkWebSocketsSection(connections: [], redaction: .standard, selected: .constant(nil))

            let rows = try filled.inspect().findAll(NetworkWebSocketRow.self).count
            let heading = try? empty.inspect().find(text: "WebSockets")

            #expect(rows == 2)
            #expect(heading == nil)
        }
    }
#endif
