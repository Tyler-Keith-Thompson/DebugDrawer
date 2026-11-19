#if DEBUG
    import Foundation
    import os
    import OSLogClient

    /// Receives os_log entries and pushes them into the shared ConsoleLogStore.
    final class ConsoleLogDriver: LogDriver, @unchecked Sendable {
        /// Entries logged before it are dropped; `nil` keeps every entry. OSLogClient calls the
        /// driver from its own actor, so it sits behind a lock. `OSAllocatedUnfairLock` rather
        /// than `Mutex`, which needs iOS 18.
        private let earliestDate = OSAllocatedUnfairLock<Date?>(initialState: nil)

        convenience init() {
            self.init(id: "com.debugdrawer.console")
        }

        /// Drops the entries logged before `date` from now on; `nil` keeps every entry.
        func ignoreEntries(before date: Date?) {
            earliestDate.withLock { $0 = date }
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
            guard earliestDate.withLock({ $0.map { date >= $0 } ?? true }) else { return }
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
