#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// A WebSocket connection in full: its URL, when it opened, the subprotocols the app offered,
    /// how it closed (by which side, the code and the reason) or why it failed, then its frames,
    /// the latest first, and a button that copies them all, with sensitive values masked.
    ///
    /// It lists the latest ``shownFrames`` frames until Show All lists the rest. It keeps whether
    /// they are shown.
    struct NetworkWebSocketDetail: View {
        /// How many frames show before Show All.
        static let shownFrames = 50

        let connection: NetworkWebSocketConnection
        let redaction: DebugDrawerRedaction
        @State var showsAllFrames = false
        let inspection = Inspection<Self>()
        @Environment(\.timeZone) private var timeZone

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                RedactedText(connection.url, redacted: redaction.redacting(url: connection.url))
                    .debugDrawerFont(.code)
                    .debugDrawerForegroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                DebugDrawerKeyValueRow("Opened", value: connection.opened.timeLabel(in: timeZone))
                if !connection.protocols.isEmpty {
                    DebugDrawerKeyValueRow("Protocols", value: connection.protocols.joined(separator: ", "))
                        .debugDrawerValueStyle(.code)
                }
                state
                DebugDrawerKeyValueRow("Frames", value: connection.frameSummary)
                if connection.droppedFrames > 0 {
                    let dropped = connection.droppedFrames.formatted()
                    Text("The earliest \(dropped) aren't kept: a connection keeps its latest \(connection.frames.count.formatted()).")
                        .debugDrawerFont(.secondary)
                        .debugDrawerForegroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .debugDrawerRowPadding()
                }

                let frames = showsAllFrames ? connection.frames : Array(connection.frames.prefix(Self.shownFrames))
                ForEach(frames) { frame in
                    NetworkWebSocketFrameRow(frame: frame, redaction: redaction)
                }

                DebugDrawerActionRow {
                    DebugDrawerCopyButton("Copy Frames") { connection.transcript(redaction: redaction, timeZone: timeZone) }
                    if !showsAllFrames, connection.frames.count > Self.shownFrames {
                        Button("Show All \(connection.frames.count.formatted())") { showsAllFrames = true }
                            .accessibilityLabel("Show All \(connection.frames.count.formatted()) Frames")
                            .accessibilityHint("Lists the frames before the latest \(Self.shownFrames)")
                    }
                }
            }
            .onReceive(inspection.notice) { inspection.visit(self, $0) }
        }

        /// Open, or who closed it with which code and reason and when, or why it failed.
        @ViewBuilder private var state: some View {
            switch connection.state {
            case .open:
                DebugDrawerKeyValueRow("State", value: "Open")
                    .debugDrawerValueStyle(.text)
            case let .closed(close):
                DebugDrawerKeyValueRow("Closed by", value: close.side == .app ? "The app" : "The server")
                    .debugDrawerValueStyle(.text)
                DebugDrawerKeyValueRow("Close code", value: close.codeLabel)
                if let reason = close.reason {
                    DebugDrawerKeyValueRow("Reason", value: reason)
                        .debugDrawerValueStyle(.text)
                }
                DebugDrawerKeyValueRow("Closed", value: close.timestamp.timeLabel(in: timeZone))
            case let .failed(message, date):
                DebugDrawerIssueRow("Connection failed", severity: .error) {
                    Text(message)
                }
                DebugDrawerKeyValueRow("Failed", value: date.timeLabel(in: timeZone))
            }
        }
    }

    extension NetworkWebSocketConnection {
        /// The count of frames and how many went each way, kept or not: "12 · 5 sent, 7 received".
        var frameSummary: String {
            "\(frameCount.formatted()) · \(sentFrames.formatted()) sent, \(receivedFrames.formatted()) received"
        }
    }

    extension Date {
        /// The time to the millisecond, on a 24-hour clock in `timeZone`: "10:42:05.123".
        func timeLabel(in timeZone: TimeZone) -> String {
            // A line break escaped with a backslash, so the format is one line.
            let format: Date.FormatString = """
            \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)\
            :\(second: .twoDigits).\(secondFraction: .fractional(3))
            """
            let style = Date.VerbatimFormatStyle(
                format: format,
                timeZone: timeZone,
                calendar: Calendar(identifier: .gregorian)
            )
            return formatted(style)
        }
    }
#endif
