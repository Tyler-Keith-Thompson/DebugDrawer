#if DEBUG
    import Foundation

    /// A log line as a session's file holds it: one JSON object per line, after the header.
    ///
    /// The line is kept as it was captured. Log text has no keys for the drawer's redaction rules
    /// to match, so the Console shows, copies and reports it as logged, and writes it so too.
    struct ConsoleSessionLine: Codable, Equatable {
        /// When it was logged, in ``ConsoleSessionHeader/dateStyle``.
        var time: String
        /// `debug`, `info`, `notice`, `error` or `fault`.
        var level: String
        /// `stdout`, `stderr` or `oslog`.
        var source: String
        /// What was logged.
        var text: String
    }

    extension ConsoleSessionLine {
        /// `line` as its file holds it.
        init(_ line: LogLine) {
            self.init(
                time: ConsoleSessionHeader.dateStyle.format(line.timestamp),
                level: line.level.name,
                source: line.source.rawValue,
                text: line.text
            )
        }

        /// The log line it holds; `nil` when its time, level or source isn't one this build reads.
        var logLine: LogLine? {
            guard let timestamp = try? ConsoleSessionHeader.dateStyle.parse(time),
                  let level = LogLine.Level(name: level),
                  let source = LogLine.Source(rawValue: source) else { return nil }
            return LogLine(timestamp: timestamp, text: text, source: source, level: level)
        }
    }

    extension LogLine.Level {
        /// The level's name in a session's file.
        fileprivate var name: String {
            switch self {
            case .debug: "debug"
            case .info: "info"
            case .notice: "notice"
            case .error: "error"
            case .fault: "fault"
            }
        }

        /// The level named `name` in a session's file.
        fileprivate init?(name: String) {
            switch name {
            case "debug": self = .debug
            case "info": self = .info
            case "notice": self = .notice
            case "error": self = .error
            case "fault": self = .fault
            default: return nil
            }
        }
    }
#endif
