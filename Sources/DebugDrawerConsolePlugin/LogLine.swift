import Foundation

public struct LogLine: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let text: String
    public let source: Source
    public let level: Level
    /// The os_log subsystem it was logged to (`com.example.shop`), or the one an app's logger
    /// gave ``ConsoleLogSink``; empty for stdout and stderr.
    public let subsystem: String
    /// The os_log category it was logged to (`networking`), or the one an app's logger gave
    /// ``ConsoleLogSink``; empty for stdout and stderr.
    public let category: String
    /// The key/value fields an app's logger attached through ``ConsoleLogSink``; empty for
    /// os_log, stdout and stderr lines.
    public let metadata: [String: String]

    /// A line as it was captured.
    ///
    /// - Parameters:
    ///   - timestamp: When it was logged.
    ///   - text: What was logged, without its subsystem or category.
    ///   - source: Where it was captured from.
    ///   - level: Its level.
    ///   - subsystem: The os_log subsystem; empty for stdout and stderr.
    ///   - category: The os_log category; empty for stdout and stderr.
    ///   - metadata: The fields the app's logger attached; empty for os_log, stdout and stderr.
    init(
        id: UUID = UUID(), timestamp: Date, text: String, source: Source, level: Level, subsystem: String = "", category: String = "",
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.text = text
        self.source = source
        self.level = level
        self.subsystem = subsystem
        self.category = category
        self.metadata = metadata
    }

    /// Where a line was captured from.
    public enum Source: String, Codable, Sendable {
        case stdout, stderr, oslog
        /// The app's own logger, through ``ConsoleLogSink``.
        case sink
    }

    public enum Level: Comparable, Codable, Sendable {
        case debug, info, notice, error, fault

        var label: String? {
            switch self {
            case .error: "ERR"
            case .fault: "FLT"
            case .debug: "DBG"
            default: nil
            }
        }
    }
}

extension LogLine {
    /// What the line costs the console's byte bound: its text and the fields beside it.
    var capturedByteCount: Int {
        text.utf8.count + subsystem.utf8.count + category.utf8.count
            + metadata.reduce(0) { $0 + $1.key.utf8.count + $1.value.utf8.count }
    }
}
