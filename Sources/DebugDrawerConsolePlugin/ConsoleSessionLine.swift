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
        /// `stdout`, `stderr`, `oslog` or `sink`.
        var source: String
        /// What was logged.
        var text: String
        /// The os_log subsystem; left out for a line without one, as stdout and stderr lines are,
        /// and read as empty when absent, as in a file an earlier build wrote.
        var subsystem: String?
        /// The os_log category; left out and read like `subsystem`.
        var category: String?
        /// The key/value fields an app's logger attached through the sink; left out when there are
        /// none, and read as none when absent, as in a file an earlier build wrote. The format
        /// stays the same: a build that doesn't know the key ignores it.
        var metadata: [String: String]?
    }

    extension ConsoleSessionLine {
        /// `line` as its file holds it.
        init(_ line: LogLine) {
            self.init(
                time: ConsoleSessionHeader.dateStyle.format(line.timestamp),
                level: line.level.name,
                source: line.source.rawValue,
                text: line.text,
                subsystem: line.subsystem.isEmpty ? nil : line.subsystem,
                category: line.category.isEmpty ? nil : line.category,
                metadata: line.metadata.isEmpty ? nil : line.metadata
            )
        }

        /// The log line it holds; `nil` when its time, level or source isn't one this build reads.
        var logLine: LogLine? {
            guard let timestamp = try? ConsoleSessionHeader.dateStyle.parse(time),
                  let level = LogLine.Level(name: level),
                  let source = LogLine.Source(rawValue: source) else { return nil }
            return LogLine(
                timestamp: timestamp, text: text, source: source, level: level, subsystem: subsystem ?? "", category: category ?? "",
                metadata: metadata ?? [:]
            )
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
