import Foundation

/// The host's adapter between the receiver's log levels capability and its own logger
/// (swift-log, CocoaLumberjack or one of its own): the hook through which a sidecar raises a
/// subsystem's verbosity for a session.
///
/// An app can't change the level the system's unified logging (os_log) keeps for its own
/// subsystems; its logger can, by choosing which entries it writes. The adapter decides what a
/// sidecar may touch: listing a subsystem in ``elevatableSubsystems()`` marks it as one an
/// employee may raise, to one of the levels listed with it. The receiver calls it on the main
/// actor, only with a listed subsystem and one of its levels, and resets only the subsystems it
/// raised: each as the session ends or expires, and those a session left when the app quit or was
/// killed as the next launch makes the capability.
///
/// ```swift
/// @MainActor
/// final class LogLevelAdapter: DebugDrawerLogLevelAdapter {
///     func elevatableSubsystems() -> [DebugDrawerLogSubsystem] {
///         [DebugDrawerLogSubsystem(name: "com.example.shop.checkout", levels: ["info", "debug", "trace"],
///                                  level: AppLog.level(of: "com.example.shop.checkout"))]
///     }
///
///     func setLevel(_ level: String, forSubsystem subsystem: String) {
///         AppLog.setLevel(level, of: subsystem)
///     }
///
///     func resetLevel(forSubsystem subsystem: String) {
///         AppLog.resetLevel(of: subsystem)
///     }
/// }
/// ```
///
/// The receiver captures no log line: the raised lines go where the logger already writes them,
/// so the redaction the logger applies (os_log's private interpolations, a handler that masks
/// fields) applies to them as to every other line. Keep it on at the verbose levels.
@MainActor
public protocol DebugDrawerLogLevelAdapter {
    /// The subsystems a sidecar may see and raise, each with the levels it may set and the level
    /// it logs at now, in the order to list them.
    func elevatableSubsystems() -> [DebugDrawerLogSubsystem]

    /// Makes the logger write `subsystem`'s entries at `level` until it is reset.
    ///
    /// - Parameters:
    ///   - level: One of the levels ``elevatableSubsystems()`` listed for the subsystem.
    ///   - subsystem: A subsystem ``elevatableSubsystems()`` listed.
    func setLevel(_ level: String, forSubsystem subsystem: String)

    /// Puts `subsystem` back at the level the app gives it on its own.
    ///
    /// - Parameter subsystem: A subsystem the receiver raised.
    func resetLevel(forSubsystem subsystem: String)
}
