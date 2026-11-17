import DebugDrawerConsolePlugin

// The macOS example has its own copy of this file: each app is its own module, and the examples
// share no code.

/// A logger of the app's own, standing in for swift-log or CocoaLumberjack: it writes through
/// neither os_log nor stdout, so the Console sees its lines only through the bridge to
/// `ConsoleLogSink`. The sink exists in release builds too, where it does nothing, so the bridge
/// needs no `#if DEBUG`.
struct ExampleLogger: Sendable {
    /// The logger's own levels, as a logging library has them.
    enum Level: Sendable {
        case trace, info, warning, error
    }

    /// Names the logger, as swift-log's label does; the Console shows it as the subsystem.
    let label: String

    /// Logs `message` with `metadata` at `level`.
    func log(_ level: Level, _ message: String, metadata: [String: String] = [:], category: String = "") {
        ConsoleLogSink.log(
            level: level.consoleLevel, message: message, metadata: metadata, subsystem: label, category: category
        )
    }

    /// The checkout's logger, which the Log Through App Logger button logs to.
    static let checkout = ExampleLogger(label: "com.example.checkout")

    /// Logs a declined payment with its order, user and card as metadata.
    static func logPaymentDeclined(_ counter: Int) {
        checkout.log(.warning, "Payment declined", metadata: ["order": "\(1040 + counter)", "user": "7", "card": "visa"], category: "payments")
    }
}

extension ExampleLogger.Level {
    /// The Console's level for the logger's: it has no warning level, as os_log has none.
    fileprivate var consoleLevel: ConsoleLogSink.Level {
        switch self {
        case .trace: .debug
        case .info: .info
        case .warning, .error: .error
        }
    }
}
