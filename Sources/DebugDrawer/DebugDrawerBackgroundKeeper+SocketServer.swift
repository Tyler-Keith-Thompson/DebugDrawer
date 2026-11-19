import Combine
import DebugDrawerReceiver

// The keeper lives in the receiver, which knows nothing of core's socket server (debug-only, with a
// stand-in that serves nothing). This overload joins the two: the keeper ends the session as the
// last viewer disconnects from the socket on its own. It compiles in release too, where the
// stand-in server never publishes a disconnection.

extension DebugDrawerBackgroundKeeper {
    /// A keeper of the app while `sessions` has one open, which also ends the session as the last
    /// sidecar disconnects from `socketServer` on its own (not when the app stops the server).
    ///
    /// ```swift
    /// let keeper = DebugDrawerBackgroundKeeper(sessions: sessions, socketServer: socketServer)
    /// ```
    ///
    /// - Parameters:
    ///   - sessions: The sessions whose state it follows.
    ///   - socketServer: The server a sidecar connects to.
    ///   - continuedProcessingIdentifierPrefix: The prefix of the continued processing task's
    ///     identifier, listed as `<prefix>.*` in the app's `BGTaskSchedulerPermittedIdentifiers`;
    ///     `nil` asks for no continued processing task.
    public convenience init(
        sessions: DebugDrawerSessions,
        socketServer: DebugDrawerSocketServer,
        continuedProcessingIdentifierPrefix: String? = DebugDrawerBackgroundKeeper.defaultContinuedProcessingPrefix
    ) {
        // The server publishes on the main actor, where it counts its viewers.
        let lastDisconnections = socketServer.viewerDisconnections
            .filter { [weak socketServer] in
                MainActor.assumeIsolated { socketServer?.viewerCount == 0 }
            }
            .eraseToAnyPublisher()
        self.init(
            sessions: sessions,
            sidecarDisconnections: lastDisconnections,
            continuedProcessingIdentifierPrefix: continuedProcessingIdentifierPrefix
        )
    }
}
