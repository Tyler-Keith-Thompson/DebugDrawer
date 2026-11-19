// The one abstraction a viewer of plugin models sees, whichever way it reaches them: the drawer
// in the app's own process, a sidecar app reading the shared app-group store while either app is
// suspended, a sidecar talking over a Unix domain socket while both run, and DD-19's remote Mac
// viewer over the network. Each hands out the same `DebugDrawerPluginTransport` a plugin's view
// already draws from, so a view never learns which it is on, and a viewer picks the transport per
// connection at run time: it holds an `any DebugDrawerTransport`. Rejected: a transport chosen by
// a compile-time flag or generic parameter (a viewer couldn't hold two at once, or switch when the
// app goes to the background), and a message-level protocol (`send`/`receive` of raw messages) as
// the public face (every viewer would redo the decoding, and the in-process one would lose
// `direct(to:)`'s synchronous commands).

/// A connection to the plugin models of an app: hands out a ``DebugDrawerPluginTransport`` for a
/// plugin, by the ID its model was registered under.
///
/// Three transports conform: ``DebugDrawerInProcessTransport`` in the app's own process,
/// ``DebugDrawerSocketTransport`` to an app that runs while the viewer does, and
/// ``DebugDrawerAppGroupStoreTransport`` to the snapshots an app left in a shared directory, read
/// even while it is suspended. The app offers its models through a ``DebugDrawerModelRegistry``,
/// which a ``DebugDrawerSocketServer`` or a ``DebugDrawerAppGroupStoreServer`` serves.
///
/// ```swift
/// let connection: any DebugDrawerTransport = isAppRunning
///     ? try DebugDrawerSocketTransport(socketPath: socketPath)
///     : try DebugDrawerAppGroupStoreTransport(directory: storeDirectory)
/// let transport = try await connection.connect(
///     toPlugin: "DebugDrawerLaunchTimePlugin.LaunchTimePlugin",
///     snapshot: LaunchTimeSnapshot.self,
///     command: LaunchTimeCommand.self
/// )
/// ```
///
/// The protocol exists in every build; release builds' conformers throw
/// ``DebugDrawerTransportError/unreachable``.
@MainActor
public protocol DebugDrawerTransport: AnyObject {
    /// A transport to the model registered as `pluginID`, once its first snapshot is in: until the
    /// app registers the model, or the store holds its snapshot, this waits.
    ///
    /// - Parameters:
    ///   - pluginID: The ID the model was registered under, usually its plugin's
    ///     ``DebugDrawerPlugin/id``.
    ///   - snapshot: The model's `Snapshot` type.
    ///   - command: The model's `Command` type.
    /// - Returns: A transport that shows each snapshot the model publishes and carries each
    ///   command to it, for as long as it lives.
    /// - Throws: ``DebugDrawerTransportError/mismatchedTypes`` when the model's snapshot isn't a
    ///   `snapshot`, ``DebugDrawerTransportError/disconnected`` when the connection closes first,
    ///   and ``DebugDrawerTransportError/cancelled`` when the waiting task is cancelled.
    func connect<Snapshot: Codable & Equatable & Sendable, Command: Codable & Sendable>(
        toPlugin pluginID: String,
        snapshot: Snapshot.Type,
        command: Command.Type
    ) async throws(DebugDrawerTransportError) -> DebugDrawerPluginTransport<Snapshot, Command>
}
