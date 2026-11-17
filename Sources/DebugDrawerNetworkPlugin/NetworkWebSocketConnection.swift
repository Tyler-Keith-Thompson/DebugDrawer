#if DEBUG
    import Foundation

    /// A WebSocket connection the app opened with `URLSessionWebSocketTask`: where to, when, the
    /// frames that went each way, the latest first, and whether it is still open.
    struct NetworkWebSocketConnection: Identifiable, Equatable, Sendable {
        /// Whether the connection is open, and how it ended when it isn't.
        enum State: Equatable, Sendable {
            case open
            /// The app or the server closed it, with a close code and maybe a reason.
            case closed(NetworkWebSocketClose)
            /// It ended with an error and no close code: the connection dropped or never opened.
            case failed(message: String, at: Date)
        }

        let id: UUID
        let url: String
        /// The subprotocols the app offered, from its `Sec-WebSocket-Protocol` header.
        let protocols: [String]
        /// When the app created the task.
        let opened: Date
        private(set) var state = State.open
        /// The frames kept, the latest first: at most the recorder's frame capacity.
        private(set) var frames: [NetworkWebSocketFrame] = []
        /// How many frames, the earliest, were let go to keep the count within the capacity.
        private(set) var droppedFrames = 0
        /// How many frames the app sent, kept or not.
        private(set) var sentFrames = 0
        /// How many frames the app received, kept or not.
        private(set) var receivedFrames = 0

        init(id: UUID = UUID(), url: String, protocols: [String] = [], opened: Date) {
            self.id = id
            self.url = url
            self.protocols = protocols
            self.opened = opened
        }

        var isOpen: Bool {
            state == .open
        }

        /// Whether it ended with an error rather than a close.
        var isFailure: Bool {
            if case .failed = state { true } else { false }
        }

        /// The host the connection is to, which the ignore list matches; empty when the URL has none.
        var host: String {
            URLComponents(string: url)?.host ?? ""
        }

        var path: String {
            URLComponents(string: url).map { $0.path.isEmpty ? "/" : $0.path } ?? url
        }

        /// How many frames went through the connection, kept or not.
        var frameCount: Int {
            sentFrames + receivedFrames
        }

        /// The connection with `frame` first, and the earliest frames let go while there are more
        /// than `capacity`; a capacity of 0 or less keeps none, and only counts them.
        mutating func record(_ frame: NetworkWebSocketFrame, capacity: Int) {
            switch frame.direction {
            case .sent: sentFrames += 1
            case .received: receivedFrames += 1
            }
            frames.insert(frame, at: 0)
            let excess = frames.count - max(capacity, 0)
            if excess > 0 {
                droppedFrames += excess
                frames.removeLast(excess)
            }
        }

        /// The connection with the frame with `frameID` marked failed for `reason`, if it is kept.
        mutating func fail(_ frameID: NetworkWebSocketFrame.ID, _ reason: String) {
            guard let index = frames.firstIndex(where: { $0.id == frameID }) else { return }
            frames[index] = frames[index].failed(reason)
        }

        /// The connection ended as `state` says, unless it had ended already: the first end is
        /// the one that happened, and what follows it (a receive cancelled by the app's close) is
        /// its consequence.
        mutating func end(_ state: State) {
            guard isOpen else { return }
            self.state = state
        }
    }

    /// How a WebSocket connection was closed: by which side, with which code and reason, and when.
    struct NetworkWebSocketClose: Equatable, Sendable {
        enum Side: Equatable, Sendable {
            case app
            case server
        }

        let side: Side
        /// The close code (RFC 6455, section 7.4); 0 when the app cancelled the task without one.
        let code: Int
        let reason: String?
        let timestamp: Date

        /// The code and what it means: "1000 Normal closure", "4000"; "None" for 0.
        var codeLabel: String {
            guard code != 0 else { return "None" }
            return Self.names[code].map { "\(code) \($0)" } ?? String(code)
        }

        /// The reason the close frame carried, as text: UTF-8 as RFC 6455 asks, or hex when it
        /// isn't; `nil` for none.
        static func reason(_ data: Data?) -> String? {
            guard let data, !data.isEmpty else { return nil }
            return String(bytes: data, encoding: .utf8) ?? data.map { String(format: "%02x", $0) }.joined(separator: " ")
        }

        /// The codes RFC 6455 and `URLSessionWebSocketTask.CloseCode` name.
        private static let names = [
            1000: "Normal closure",
            1001: "Going away",
            1002: "Protocol error",
            1003: "Unsupported data",
            1005: "No status received",
            1006: "Abnormal closure",
            1007: "Invalid frame payload data",
            1008: "Policy violation",
            1009: "Message too big",
            1010: "Mandatory extension missing",
            1011: "Internal server error",
            1015: "TLS handshake failure"
        ]
    }
#endif
