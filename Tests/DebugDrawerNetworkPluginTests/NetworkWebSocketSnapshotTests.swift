// Views render on the Mac; the snapshot packages are linked on Apple platforms only.
#if os(macOS)
    @testable import DebugDrawerNetworkPlugin
    import SnapshotTesting
    import SwiftUI
    import Testing

    // The rows draw SwiftUI's own views, so ImageRenderer draws them, at 316 points, the width of
    // the drawer on an iPad and the narrowest it gets. macOS doesn't scale text with Dynamic Type,
    // so the Mac pins light and dark only.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct NetworkWebSocketSnapshotTests {
        @Test(
            "A closed connection's detail: who closed it, the code and reason, then its frames with arrows, times, sizes and previews",
            arguments: [ColorScheme.light, .dark]
        )
        func closedConnection(colorScheme: ColorScheme) throws {
            let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
            var connection = NetworkWebSocketConnection(url: "wss://chat.example.com/v1/room?token=secret", protocols: ["chat"], opened: start)
            let frames = [
                NetworkWebSocketFrame(
                    direction: .sent, kind: .text, payload: Data(#"{"type":"join","token":"abc123"}"#.utf8),
                    timestamp: start + 0.120
                ),
                NetworkWebSocketFrame(
                    direction: .received, kind: .text, payload: Data(#"{"type":"joined","room":"general"}"#.utf8),
                    timestamp: start + 0.184
                ),
                NetworkWebSocketFrame(direction: .sent, kind: .binary, payload: Data(0 ..< 40), timestamp: start + 1.002),
                NetworkWebSocketFrame(direction: .received, kind: .binary, payload: Data([0xCA, 0xFE]), timestamp: start + 1.010),
                NetworkWebSocketFrame(direction: .sent, kind: .ping, timestamp: start + 2),
                NetworkWebSocketFrame(direction: .received, kind: .pong, timestamp: start + 2.004)
            ]
            for frame in frames {
                connection.record(frame, capacity: 500)
            }
            connection.end(.closed(NetworkWebSocketClose(side: .server, code: 1001, reason: "Server restarting", timestamp: start + 3)))
            let sut = NetworkWebSocketRow(connection: connection, redaction: .standard, isSelected: true, onSelect: {})
            let renderer = ImageRenderer(content: sut
                .environment(\.locale, Locale(identifier: "en_US"))
                .environment(\.timeZone, TimeZone(identifier: "UTC") ?? .gmt)
                .frame(width: 316, alignment: .leading)
                .padding()
                .background(.background)
                .environment(\.colorScheme, colorScheme))
            renderer.scale = 2

            let actual = try #require(renderer.nsImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
        }

        @Test(
            "The WebSockets section: an open connection, one that failed with its glyph, and one closed by the app",
            arguments: [ColorScheme.light, .dark]
        )
        func webSocketSection(colorScheme: ColorScheme) throws {
            let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
            var open = NetworkWebSocketConnection(url: "wss://chat.example.com/v1/room", opened: start)
            for index in 0 ..< 12 {
                open.record(
                    NetworkWebSocketFrame(direction: .received, kind: .text, payload: Data("tick \(index)".utf8), timestamp: start),
                    capacity: 500
                )
            }
            var failed = NetworkWebSocketConnection(url: "wss://prices.example.com/v2/stream/quotes/live", opened: start)
            failed.end(.failed(message: "The network connection was lost.", at: start + 1))
            var closed = NetworkWebSocketConnection(url: "wss://chat.example.com/v1/presence", opened: start)
            closed.record(NetworkWebSocketFrame(direction: .sent, kind: .text, payload: Data("hi".utf8), timestamp: start), capacity: 500)
            closed.end(.closed(NetworkWebSocketClose(side: .app, code: 1000, reason: nil, timestamp: start + 2)))
            let sut = NetworkWebSocketsSection(connections: [open, failed, closed], redaction: .standard, selected: .constant(nil))
            let renderer = ImageRenderer(content: sut
                .environment(\.locale, Locale(identifier: "en_US"))
                .frame(width: 316, alignment: .leading)
                .padding()
                .background(.background)
                .environment(\.colorScheme, colorScheme))
            renderer.scale = 2

            let actual = try #require(renderer.nsImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
        }
    }
#endif
