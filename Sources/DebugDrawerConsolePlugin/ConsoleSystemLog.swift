#if DEBUG
    import Foundation
    import os
    import OSLogClient

    /// The system's log as the next launch reads it: the os_log lines an earlier launch's process
    /// logged after its session's last one, which it hadn't read from its own log when it ended.
    ///
    /// A process reads its own log only every two seconds (OSLogClient), so a crash or a kill
    /// costs its session the lines of up to that long before; the next launch finds them here.
    protocol ConsoleSystemLog: Sendable {
        /// The os_log lines the process `processIdentifier` logged at or after `date`, oldest first.
        ///
        /// - Parameters:
        ///   - processIdentifier: The earlier launch's process.
        ///   - date: The time of the last os_log line its session kept, or when the session
        ///     started.
        /// - Returns: ``ConsoleEarlierProcess/running`` while that process still runs, as another
        ///   instance of the app; otherwise its lines, none where the system's log can't be read.
        func lines(loggedBy processIdentifier: Int32, since date: Date) -> ConsoleEarlierProcess
    }

    /// What became of the process that wrote an earlier session, as the system's log tells it.
    enum ConsoleEarlierProcess: Sendable {
        /// It still runs, and still writes its session.
        case running
        /// It ended, having logged these lines after its session's last os_log line.
        case ended([LogLine])
    }

    /// The system's log through `OSLogStore`: on macOS, the store of the whole system, which an
    /// app outside the App Sandbox, run by an administrator, may read; elsewhere a process reads
    /// only its own, so an earlier launch's lines can't be found.
    struct _ConsoleSystemLog: ConsoleSystemLog {
        private static let logger = Logger(subsystem: "DebugDrawerConsolePlugin", category: "ConsoleSystemLog")

        func lines(loggedBy processIdentifier: Int32, since date: Date) -> ConsoleEarlierProcess {
            // Signal 0 checks only that the process exists. EPERM means one does that this
            // process may not signal: perhaps another process given the same identifier since,
            // which can't be told apart from the app, so its session is left alone.
            if kill(processIdentifier, 0) == 0 || errno == EPERM {
                return .running
            }
            #if os(macOS)
                do {
                    return try .ended(Self.read(processIdentifier, since: date))
                } catch {
                    // At most once a launch, as each launch reads the log once.
                    Self.logger.notice("The last os_log lines of the earlier launch weren't read: \(error.localizedDescription, privacy: .public)")
                    return .ended([])
                }
            #else
                // iOS, Mac Catalyst included, and the other platforms offer only the current
                // process's store.
                return .ended([])
            #endif
        }

        #if os(macOS)
            /// The lines from the system's store: the process identifier and the time narrow the
            /// read in the store, and the name keeps out a later process given the same
            /// identifier, as every launch of the app has the same name.
            private static func read(_ processIdentifier: Int32, since date: Date) throws -> [LogLine] {
                let store = try OSLogStore(scope: .system)
                let predicate = NSPredicate(format: "processIdentifier == %d AND date >= %@", processIdentifier, date as NSDate)
                let processName = ProcessInfo.processInfo.processName
                return try store.getEntries(at: store.position(date: date), matching: predicate)
                    .compactMap { $0 as? OSLogEntryLog }
                    .filter { $0.process == processName }
                    .map { entry in
                        ConsoleLogDriver.line(
                            level: LogDriver.LogLevel(entry.level),
                            subsystem: entry.subsystem,
                            category: entry.category,
                            date: entry.date,
                            message: entry.composedMessage
                        )
                    }
            }
        #endif
    }
#endif
