#if DEBUG
    import DebugDrawer
    import Foundation

    extension HTTPArchive.Entry {
        /// The archive's entry for a WebSocket connection, as Chrome DevTools writes one: the
        /// handshake as a GET answered 101, `_resourceType` `websocket`, and the text and binary
        /// messages in `_webSocketMessages`, the earliest first. Pings and pongs are left out, as
        /// DevTools leaves them out.
        ///
        /// The URL and JSON text messages are masked as `redaction` says. A message larger than
        /// ``NetworkWebSocketFrame/keptBytes`` is listed with empty data, since the part kept can't
        /// be read as JSON to mask. A connection that failed with no frames has status 0, no
        /// answer, as a request that got none does.
        init(_ connection: NetworkWebSocketConnection, redaction: DebugDrawerRedaction) {
            let url = redaction.redacting(url: connection.url)
            let end = switch connection.state {
            case .open: connection.frames.first?.timestamp ?? connection.opened
            case let .closed(close): close.timestamp
            case let .failed(_, date): date
            }
            let time = max(end.timeIntervalSince(connection.opened), 0) * 1000
            let answered = !connection.isFailure || !connection.frames.isEmpty
            var headers: [HTTPArchive.NameValue] = []
            if !connection.protocols.isEmpty {
                headers.append(HTTPArchive.NameValue(name: "Sec-WebSocket-Protocol", value: connection.protocols.joined(separator: ", ")))
            }

            self.init(
                startedDateTime: HTTPArchive.dateStyle.format(connection.opened),
                time: time,
                request: HTTPArchive.Request(
                    method: "GET",
                    url: url,
                    httpVersion: "HTTP/1.1",
                    headers: headers,
                    queryString: (URLComponents(string: url)?.queryItems ?? []).map {
                        HTTPArchive.NameValue(name: $0.name, value: $0.value ?? "")
                    },
                    bodySize: 0
                ),
                response: HTTPArchive.Response(
                    status: answered ? 101 : 0,
                    statusText: answered ? "Switching Protocols" : "",
                    httpVersion: "HTTP/1.1",
                    headers: [],
                    content: HTTPArchive.Content(size: 0, mimeType: ""),
                    bodySize: 0
                ),
                timings: HTTPArchive.Timings(dns: -1, connect: -1, ssl: -1, send: 0, wait: time, receive: 0),
                error: { if case let .failed(message, _) = connection.state { message } else { nil } }(),
                comment: connection.archiveComment,
                resourceType: "websocket",
                webSocketMessages: connection.frames.reversed().compactMap { $0.archiveMessage(redaction: redaction) }
            )
        }
    }

    extension NetworkWebSocketConnection {
        /// How the connection closed, and how many frames weren't kept, in sentences; `nil` while
        /// it is open with every frame kept.
        fileprivate var archiveComment: String? {
            var notes: [String] = []
            if case let .closed(close) = state {
                let side = close.side == .app ? "the app" : "the server"
                notes.append("Closed by \(side): \(close.codeLabel)" + (close.reason.map { ", “\($0)”" } ?? ""))
            }
            if droppedFrames > 0 {
                notes.append("The earliest \(droppedFrames) frames weren't kept")
            }
            return notes.isEmpty ? nil : notes.joined(separator: ". ")
        }
    }

    extension NetworkWebSocketFrame {
        /// The frame as a `_webSocketMessages` message; `nil` for a ping or a pong.
        fileprivate func archiveMessage(redaction: DebugDrawerRedaction) -> HTTPArchive.WebSocketMessage? {
            let data: String
            switch kind {
            case .text: data = redactedText(redaction) ?? ""
            case .binary: data = isWhole ? payload.base64EncodedString() : ""
            case .ping, .pong: return nil
            }
            return HTTPArchive.WebSocketMessage(
                type: direction == .sent ? "send" : "receive",
                time: timestamp.timeIntervalSince1970,
                opcode: kind == .text ? 1 : 2,
                data: data
            )
        }
    }
#endif
