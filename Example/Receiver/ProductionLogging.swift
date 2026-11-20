import Combine
import DebugDrawerReceiver
import os

/// The example's logger: a level per subsystem, below which it writes nothing, which a sidecar
/// raises for its session through the log levels capability. It writes through os_log with the
/// customer's details private, so a raised level shows more lines, never their unredacted values.
@MainActor
final class ProductionLogging: ObservableObject, DebugDrawerLogLevelAdapter {
    /// The levels the logger knows, from the least to the most verbose.
    static let levels = ["notice", "info", "debug"]
    static let checkout = "com.debugdrawer.example.receiver.checkout"
    static let sync = "com.debugdrawer.example.receiver.sync"
    private static let defaultLevel = "notice"

    @Published private var raised: [String: String] = [:]
    /// The levels the last Log Checkout Step wrote lines at.
    @Published private(set) var lastWritten: [String] = []

    func level(of subsystem: String) -> String {
        raised[subsystem] ?? Self.defaultLevel
    }

    /// Logs a checkout step at every level, as the app's code would; the subsystem's level decides
    /// which lines are written.
    func logCheckoutStep(customer: String) {
        let logger = Logger(subsystem: Self.checkout, category: "Checkout")
        let threshold = Self.levels.firstIndex(of: level(of: Self.checkout)) ?? 0
        var written: [String] = []
        for (index, level) in Self.levels.enumerated() where index <= threshold {
            switch level {
            case "debug": logger.debug("Cart priced for \(customer, privacy: .private)")
            case "info": logger.info("Payment sheet shown for \(customer, privacy: .private)")
            default: logger.notice("Checkout step completed")
            }
            written.append(level)
        }
        lastWritten = written
    }

    func elevatableSubsystems() -> [DebugDrawerLogSubsystem] {
        [Self.checkout, Self.sync].map { DebugDrawerLogSubsystem(name: $0, levels: Self.levels, level: level(of: $0)) }
    }

    func setLevel(_ level: String, forSubsystem subsystem: String) {
        raised[subsystem] = level
    }

    func resetLevel(forSubsystem subsystem: String) {
        raised[subsystem] = nil
    }
}
