import Foundation

/// Why a ``DebugDrawerTransport`` couldn't connect to a plugin's model, or a server couldn't
/// start.
///
/// It exists in every build; release builds throw ``unreachable`` from every connection. Its
/// `localizedDescription` says what happened and what to do about it.
public enum DebugDrawerTransportError: Error, Equatable, Sendable {
    /// Nothing answers where the transport looked: no server listens on the socket, or the store's
    /// directory can't be read. Release builds, which carry nothing, throw this too.
    case unreachable
    /// The socket's file name, its path's last component, is longer than the 103 bytes a Unix
    /// domain socket's address holds. A longer path is fine.
    case socketPathTooLong
    /// A server couldn't take its socket or store: the path is in use by something else, or the
    /// directory can't be created.
    case cannotServe
    /// The connection closed before the plugin's first snapshot arrived.
    case disconnected
    /// The plugin's snapshot didn't decode as the type asked for, or the model registered under
    /// its ID has other `Snapshot` and `Command` types.
    case mismatchedTypes
    /// The task waiting for the plugin's first snapshot was cancelled.
    case cancelled
    /// The other side speaks a protocol version this build no longer speaks, or doesn't speak
    /// yet: builds one major version apart connect, and two apart don't. The connection is closed.
    case incompatibleVersion
    /// The system refused access to the socket or the store's directory (EACCES or EPERM): the
    /// app group is missing from this app's `com.apple.security.application-groups` entitlement,
    /// the person declined macOS's prompt to let this app reach another app's data, or the files'
    /// permissions don't allow it. Nothing was written, here or anywhere else.
    case accessDenied
    /// The system gave no container for the app group: the group isn't in this app's
    /// `com.apple.security.application-groups` entitlement, or the app isn't signed with it.
    case noAppGroupContainer
}

extension DebugDrawerTransportError: LocalizedError {
    /// What happened, and what to do about it.
    public var errorDescription: String? {
        switch self {
        case .unreachable:
            "Nothing answers where the transport looked: the app isn't serving, or this is a release build."
        case .socketPathTooLong:
            "The socket's file name is longer than the 103 bytes a Unix domain socket's address holds. Use a shorter file name."
        case .cannotServe:
            "The server couldn't take its socket or store: something else is at the path, or the directory can't be made."
        case .disconnected:
            "The connection closed before the plugin's first snapshot arrived."
        case .mismatchedTypes:
            "The plugin's model has other Snapshot and Command types than the ones asked for."
        case .cancelled:
            "The connection was cancelled."
        case .incompatibleVersion:
            "The app and the viewer speak protocol versions two or more major versions apart. Update the older one."
        case .accessDenied:
            """
            Access to the app group's container was denied. Add the group to both apps' \
            com.apple.security.application-groups entitlement and sign both with the same team; on macOS, prefix the group \
            with the team ID or list it in a provisioning profile, and if macOS asked whether this app may access data from \
            other apps and was told no, run tccutil reset SystemPolicyAppData <bundle ID> and allow it when asked again.
            """
        case .noAppGroupContainer:
            """
            The system gave no container for the app group. Add the group to this app's \
            com.apple.security.application-groups entitlement and sign the app with it.
            """
        }
    }
}
