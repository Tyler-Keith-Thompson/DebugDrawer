#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// One frame in a connection's detail: ↑ for sent or ↓ for received, the time to the
    /// millisecond, the kind and size, then a preview: a text frame's start, with what the
    /// redaction rules call sensitive in JSON masked until revealed, or a binary frame's first
    /// bytes in hex. A frame that couldn't be sent says why.
    struct NetworkWebSocketFrameRow: View {
        let frame: NetworkWebSocketFrame
        let redaction: DebugDrawerRedaction
        @Environment(\.timeZone) private var timeZone
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(frame.direction == .sent ? "↑" : "↓")
                    .debugDrawerFont(.value)
                    .debugDrawerForegroundStyle(frame.direction == .sent ? .accent : .secondary)
                    .accessibilityLabel(frame.direction == .sent ? "Sent" : "Received")
                VStack(alignment: .leading, spacing: 1) {
                    // At accessibility text sizes the time and the kind each take a line.
                    let layout = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 1))
                        : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
                    layout {
                        Text(frame.timeLabel(in: timeZone))
                            .debugDrawerFont(.value)
                            .debugDrawerForegroundStyle(.tertiary)
                        Text(frame.kindLabel)
                            .debugDrawerFont(.label)
                            .debugDrawerForegroundStyle(.secondary)
                    }
                    preview
                    if let failure = frame.failure {
                        Text(frame.kind == .ping ? "No pong: \(failure)" : "Not sent: \(failure)")
                            .debugDrawerFont(.secondary)
                            .debugDrawerForegroundStyle(.error)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .debugDrawerRowPadding()
            // Read as one item: "Sent, 10:42:05.123, Text · 5 B, hello".
            .accessibilityElement(children: .combine)
        }

        @ViewBuilder private var preview: some View {
            if let text = frame.text {
                RedactedText(
                    NetworkWebSocketFrame.textPreview(text, isWhole: frame.isWhole),
                    redacted: NetworkWebSocketFrame.textPreview(frame.redactedText(redaction) ?? text, isWhole: frame.isWhole)
                )
                .debugDrawerFont(.code)
                .debugDrawerForegroundStyle(.primary)
                .lineLimit(4)
            } else if frame.kind == .binary, frame.size > 0 {
                Text(frame.hexPreview)
                    .debugDrawerFont(.code)
                    .debugDrawerForegroundStyle(.primary)
                    .accessibilityLabel("Starts with bytes \(frame.hexPreview)")
            }
        }
    }

    extension NetworkWebSocketFrame {
        /// When it went, to the millisecond, on a 24-hour clock in `timeZone`: "10:42:05.123".
        func timeLabel(in timeZone: TimeZone) -> String {
            timestamp.timeLabel(in: timeZone)
        }

        /// The kind and, for a message, the size: "Text · 5 B", "Binary · 2 KB", "Ping", "Pong".
        var kindLabel: String {
            switch kind {
            case .text: "Text · \(sizeLabel)"
            case .binary: "Binary · \(sizeLabel)"
            case .ping: "Ping"
            case .pong: "Pong"
            }
        }

        /// A text frame's text with what `redaction` calls sensitive masked, when it is JSON kept
        /// whole; `nil` for a frame of any other kind or not kept whole, which can't be read as
        /// JSON to mask.
        func redactedText(_ redaction: DebugDrawerRedaction) -> String? {
            guard kind == .text, isWhole else { return nil }
            return String(bytes: redaction.redacting(json: payload), encoding: .utf8)
        }
    }
#endif
