import Foundation

/// Why a ``DebugDrawerReceiver`` couldn't start.
public enum DebugDrawerReceiverError: Error, Equatable, Sendable {
    /// The store's directories couldn't be made or watched: the app group's container is missing,
    /// or the app may not write there.
    case cannotServe
}
