#if DEBUG
    import Foundation

    /// One message a WebSocket connection sent or received, or a ping the app sent and the pong
    /// that answered it: which way it went, what kind it was, its size and when.
    ///
    /// The frame keeps the first ``keptBytes`` of its payload, enough for a preview, a copy and an
    /// export of the messages most apps send, while a stream of large frames stays bounded.
    struct NetworkWebSocketFrame: Identifiable, Equatable, Codable, Sendable {
        enum Direction: Equatable, Codable, Sendable {
            case sent
            case received
        }

        enum Kind: Equatable, Codable, Sendable {
            case text
            case binary
            case ping
            case pong
        }

        /// The most payload bytes a frame keeps.
        static let keptBytes = 16 * 1024
        /// The most bytes a hex preview shows.
        static let previewBytes = 16
        /// The most characters a text preview shows.
        static let previewCharacters = 200

        let id: UUID
        let direction: Direction
        let kind: Kind
        /// The payload's whole size in bytes, kept or not.
        let size: Int
        /// When the app sent it, or when the app's receive got it.
        let timestamp: Date
        /// The first ``keptBytes`` of the payload.
        let payload: Data
        /// Why it couldn't be sent, or why the pong never came; `nil` when it went through.
        let failure: String?

        /// - Parameters:
        ///   - payload: The whole payload; only its first ``keptBytes`` are kept.
        init(
            id: UUID = UUID(),
            direction: Direction,
            kind: Kind,
            payload: Data = Data(),
            timestamp: Date,
            failure: String? = nil
        ) {
            self.init(
                id: id, direction: direction, kind: kind, size: payload.count, kept: payload.kept,
                timestamp: timestamp, failure: failure
            )
        }

        /// - Parameters:
        ///   - size: The whole payload's size in bytes.
        ///   - kept: The payload's first bytes, at most ``keptBytes``.
        private init(id: UUID, direction: Direction, kind: Kind, size: Int, kept: Data, timestamp: Date, failure: String?) {
            self.id = id
            self.direction = direction
            self.kind = kind
            self.size = size
            self.timestamp = timestamp
            payload = kept
            self.failure = failure
        }

        /// The same frame, failed for `reason`.
        func failed(_ reason: String) -> Self {
            Self(id: id, direction: direction, kind: kind, size: size, kept: payload, timestamp: timestamp, failure: reason)
        }

        /// Whether the frame kept its whole payload.
        var isWhole: Bool {
            payload.count == size
        }

        /// A text frame's text, as much as was kept; `nil` for any other kind. The kept part of a
        /// longer text may end partway through a character, which is left out.
        var text: String? {
            guard kind == .text else { return nil }
            // A UTF-8 character is at most 4 bytes, so at most 3 of one can be cut off.
            return (0 ... 3).lazy.compactMap { String(bytes: payload.dropLast($0), encoding: .utf8) }.first ?? ""
        }

        /// The size as the log shows sizes: "5 B", "12 KB", "1.5 MB".
        var sizeLabel: String {
            if size < 1024 { return "\(size) B" }
            if size < 1024 * 1024 { return "\(size / 1024) KB" }
            return String(format: "%.1f MB", Double(size) / (1024 * 1024))
        }

        /// The first ``previewBytes`` of the payload as lowercase hex pairs, a space between
        /// bytes, and " …" after them when the payload is longer: "68 65 6c 6c 6f".
        var hexPreview: String {
            let bytes = payload.prefix(Self.previewBytes).map { String(format: "%02x", $0) }.joined(separator: " ")
            return size > Self.previewBytes ? bytes + " …" : bytes
        }

        /// What the frame's row shows of `text`: its first ``previewCharacters`` characters, its
        /// line breaks as spaces, and "…" after them when there is more.
        static func textPreview(_ text: String, isWhole: Bool = true) -> String {
            let flattened = text.replacing(/\s*\n\s*/, with: " ")
            let preview = String(flattened.prefix(previewCharacters))
            return preview.count < flattened.count || !isWhole ? preview + "…" : preview
        }
    }

    extension NetworkWebSocketFrame {
        /// The frame for a message the app sent or received, of the message's kind and payload.
        /// Only the kept bytes of a long text are copied.
        init(_ message: __NSURLSessionWebSocketMessage, direction: Direction, timestamp: Date) {
            if message.type == .string, let text = message.string {
                self.init(
                    id: UUID(), direction: direction, kind: .text, size: text.utf8.count, kept: Data(text.utf8.prefix(Self.keptBytes)),
                    timestamp: timestamp, failure: nil
                )
            } else {
                self.init(direction: direction, kind: .binary, payload: message.data ?? Data(), timestamp: timestamp)
            }
        }
    }

    extension Data {
        /// The first ``NetworkWebSocketFrame/keptBytes`` bytes, copied: a slice would hold on to the
        /// whole payload.
        fileprivate var kept: Data {
            count <= NetworkWebSocketFrame.keptBytes ? self : withUnsafeBytes { Data($0.prefix(NetworkWebSocketFrame.keptBytes)) }
        }
    }
#endif
