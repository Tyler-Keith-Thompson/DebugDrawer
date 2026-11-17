#if DEBUG
    import Foundation
    import OSLogClient

    /// Receives os_log entries and pushes them into the shared ConsoleLogStore.
    final class ConsoleLogDriver: LogDriver, @unchecked Sendable {
        convenience init() {
            self.init(id: "com.debugdrawer.console")
        }

        #if os(macOS)
            override func processLog(
                level: LogLevel,
                subsystem: String,
                category: String,
                date: Date,
                message: String,
                components _: [OSLogMessageComponent]
            ) {
                handleLog(level: level, subsystem: subsystem, category: category, date: date, message: message)
            }
        #else
            override func processLog(
                level: LogLevel,
                subsystem: String,
                category: String,
                date: Date,
                message: String
            ) {
                handleLog(level: level, subsystem: subsystem, category: category, date: date, message: message)
            }
        #endif

        private func handleLog(level: LogLevel, subsystem: String, category: String, date: Date, message: String) {
            let line = Self.line(level: level, subsystem: subsystem, category: category, date: date, message: message)
            Task { @MainActor in
                ConsoleLogStore.shared.ingest(line)
            }
        }

        /// The console's line for an os_log entry: its message as the text, and its subsystem and
        /// category as fields of their own, so the console can filter and mute by them.
        static func line(level: LogLevel, subsystem: String, category: String, date: Date, message: String) -> LogLine {
            let mapped: LogLine.Level = switch level {
            case .debug: .debug
            case .info: .info
            case .notice: .notice
            case .error: .error
            case .fault: .fault
            case .undefined: .info
            }
            return LogLine(timestamp: date, text: message, source: .oslog, level: mapped, subsystem: subsystem, category: category)
        }
    }
#endif
