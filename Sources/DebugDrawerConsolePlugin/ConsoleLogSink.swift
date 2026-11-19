import Foundation

/// Where an app's own logger sends its entries for the Console to show, beside os_log, stdout and
/// stderr: the bridge from swift-log, CocoaLumberjack or a logger of the app's own, which the app
/// writes.
///
/// ```swift
/// ConsoleLogSink.log(
///     level: .error, message: "Payment declined", metadata: ["order": "1042"],
///     subsystem: "com.example.shop", category: "checkout"
/// )
/// ```
///
/// The type exists in every build, so a bridge compiles unchanged in release, where
/// ``log(level:message:metadata:subsystem:category:)`` does nothing and evaluates none of its
/// arguments.
public enum ConsoleLogSink {
    /// How severe a line is, as the Console's level filter reads it.
    public enum Level: Sendable, CaseIterable {
        /// Detail for debugging; the Console dims it.
        case debug
        /// An ordinary event.
        case info
        /// An event worth noticing.
        case notice
        /// A failure; the Console marks it with the error glyph.
        case error
        /// A failure in the app's own logic; the Console marks it with the error glyph.
        case fault
    }

    /// Adds a line to the Console at the time of the call, in debug builds only. In release it does
    /// nothing and evaluates none of its arguments.
    ///
    /// Call it from any thread or actor, as a logger's backend does; it returns at once. On the
    /// main thread the line is added before it returns; from any other, lines arrive in the order
    /// the thread logged them. Lines logged before `installConsole()` are kept and shown once the
    /// Console is installed.
    ///
    /// - Parameters:
    ///   - level: How severe the line is.
    ///   - message: What was logged.
    ///   - metadata: Key/value fields, shown after the message as `key=value`, sorted by key, and
    ///     searched with it.
    ///   - subsystem: What logged it, shown and muted like an os_log subsystem: a swift-log
    ///     logger's label, say (`com.example.shop`); empty for none.
    ///   - category: Its category within the subsystem, shown and muted like an os_log
    ///     category; empty for none.
    public static func log(
        level: Level,
        message: @autoclosure () -> String,
        metadata: @autoclosure () -> [String: String] = [:],
        subsystem: @autoclosure () -> String = "",
        category: @autoclosure () -> String = ""
    ) {
        #if DEBUG
            ingest(LogLine(
                timestamp: Date(), text: message(), source: .sink, level: LogLine.Level(level),
                subsystem: subsystem(), category: category(), metadata: metadata()
            ))
        #endif
    }
}

#if DEBUG
    extension ConsoleLogSink {
        /// Hands `line` to the store capture goes to, which lives on the main actor: the latest
        /// install's, or the shared store before any.
        private static func ingest(_ line: LogLine) {
            if Thread.isMainThread {
                MainActor.assumeIsolated { ConsoleCapture.store.ingest(line) }
            } else {
                // The main queue runs blocks in the order they were submitted, so a logger
                // thread's lines arrive in the order it logged them; a task per line promises no
                // order.
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { ConsoleCapture.store.ingest(line) }
                }
            }
        }
    }

    extension LogLine.Level {
        /// The Console's level for a sink's `level`.
        init(_ level: ConsoleLogSink.Level) {
            self = switch level {
            case .debug: .debug
            case .info: .info
            case .notice: .notice
            case .error: .error
            case .fault: .fault
            }
        }
    }
#endif
