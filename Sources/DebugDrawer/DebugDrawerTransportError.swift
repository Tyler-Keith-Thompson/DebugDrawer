/// Why a ``DebugDrawerTransport`` couldn't connect to a plugin's model, or a server couldn't
/// start.
///
/// It exists in every build; release builds throw ``unreachable`` from every connection.
public enum DebugDrawerTransportError: Error, Equatable, Sendable {
    /// Nothing answers where the transport looked: no server listens on the socket, or the store's
    /// directory can't be read. Release builds, which carry nothing, throw this too.
    case unreachable
    /// The socket's path is longer than the 103 bytes a Unix domain socket's address holds.
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
}
