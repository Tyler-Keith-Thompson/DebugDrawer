import Foundation

/// A subsystem of the host's logger whose level a sidecar may raise: its name, the levels a
/// sidecar may set it to and the level it logs at now.
///
/// Levels are the host logger's own names ("debug", "trace", "verbose"), since loggers name and
/// order them differently; the receiver only checks that a level a sidecar sends is one of
/// ``levels``.
public struct DebugDrawerLogSubsystem: Codable, Equatable, Sendable {
    /// Identifies the subsystem to the host's logger ("com.example.shop.checkout").
    public let name: String
    /// The levels a sidecar may set, in the order to list them, usually from the least to the
    /// most verbose ("info", "debug", "trace").
    public let levels: [String]
    /// The level the subsystem logs at now, a raised one included.
    public let level: String

    /// A subsystem.
    ///
    /// - Parameters:
    ///   - name: Identifies the subsystem to the host's logger.
    ///   - levels: The levels a sidecar may set, in the order to list them.
    ///   - level: The level the subsystem logs at now, a raised one included.
    public init(name: String, levels: [String], level: String) {
        self.name = name
        self.levels = levels
        self.level = level
    }
}
