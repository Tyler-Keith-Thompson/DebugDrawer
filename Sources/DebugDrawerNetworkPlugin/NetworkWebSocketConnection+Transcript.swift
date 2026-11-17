#if DEBUG
    import DebugDrawer
    import Foundation

    extension NetworkWebSocketConnection {
        /// The connection as text to paste into a bug report: its URL, when it opened and how it
        /// ended, then a line per frame kept, the earliest first, with what `redaction` calls
        /// sensitive masked in the URL and in JSON text frames.
        ///
        /// ```
        /// WebSocket wss://chat.example.com/v1/room?token=%5BREDACTED%5D
        /// Opened 10:42:05.120
        /// Closed by the server at 10:42:09.004: 1000 Normal closure, "bye"
        /// ↑ 10:42:05.123 Text · 27 B: {"token":"[REDACTED]"}
        /// ↓ 10:42:05.130 Binary · 3 B: 01 02 03
        /// ```
        ///
        /// A text frame larger than ``NetworkWebSocketFrame/keptBytes`` shows no text, since the
        /// part kept can't be read as JSON to mask. Times are to the millisecond in `timeZone`.
        func transcript(redaction: DebugDrawerRedaction, timeZone: TimeZone) -> String {
            var lines = [
                "WebSocket \(redaction.redacting(url: url))",
                "Opened \(opened.timeLabel(in: timeZone))"
            ]
            if !protocols.isEmpty {
                lines.append("Protocols \(protocols.joined(separator: ", "))")
            }
            switch state {
            case .open:
                lines.append("Open")
            case let .closed(close):
                let side = close.side == .app ? "the app" : "the server"
                let reason = close.reason.map { ", \"\($0)\"" } ?? ""
                lines.append("Closed by \(side) at \(close.timestamp.timeLabel(in: timeZone)): \(close.codeLabel)\(reason)")
            case let .failed(message, date):
                lines.append("Failed at \(date.timeLabel(in: timeZone)): \(message)")
            }
            if droppedFrames > 0 {
                lines.append("The earliest \(droppedFrames) frames aren't kept")
            }
            lines += frames.reversed().map { $0.transcriptLine(redaction: redaction, timeZone: timeZone) }
            return lines.joined(separator: "\n")
        }
    }

    extension NetworkWebSocketFrame {
        /// "↑ 10:42:05.123 Text · 5 B: hello", with the failure at the end when there was one.
        fileprivate func transcriptLine(redaction: DebugDrawerRedaction, timeZone: TimeZone) -> String {
            let arrow = direction == .sent ? "↑" : "↓"
            let content: String? = switch kind {
            case .text: redactedText(redaction) ?? "(larger than \(Self.keptBytes / 1024) KB, not kept)"
            case .binary: size > 0 ? hexPreview : nil
            case .ping, .pong: nil
            }
            let failure = failure.map { kind == .ping ? " (no pong: \($0))" : " (not sent: \($0))" } ?? ""
            return "\(arrow) \(timeLabel(in: timeZone)) \(kindLabel)\(content.map { ": \($0)" } ?? "")\(failure)"
        }
    }
#endif
