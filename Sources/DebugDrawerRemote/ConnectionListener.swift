import DebugDrawer
import Network

// The server's seam to the network: what listens, and what advertises. A protocol with
// Network.framework's listener behind it, so a test can see that nothing listens or advertises
// until the app starts the server, and what would be advertised, without either happening on the
// machine running it.

#if DEBUG
    /// What a listener is asked for: where to listen, and the Bonjour service to advertise, if
    /// any.
    struct ListenerRequest: Equatable, Sendable {
        /// The TCP port, or `nil` for one the system picks.
        var port: UInt16?
        /// Whether to listen on 127.0.0.1 only.
        var loopbackOnly: Bool
        /// The service's name (`nil` for the device's), and its TXT record; `nil` advertises
        /// nothing.
        var advertisement: Advertisement?

        /// A Bonjour service to advertise.
        struct Advertisement: Equatable, Sendable {
            var name: String?
            var txtRecord: [String: String]
        }
    }

    /// Listens for TCP connections, and advertises them over Bonjour when asked.
    @MainActor
    protocol ConnectionListener: AnyObject {
        /// Starts listening as `request` says, handing each new connection to `accept` on any
        /// queue, and returns the port once listening. Called again only after ``cancel()``.
        ///
        /// - Throws: ``DebugDrawerTransportError/cannotServe`` when the system refuses to listen
        ///   there (the port is taken, say).
        func listen(
            _ request: ListenerRequest,
            accept: @escaping @Sendable (NWConnection) -> Void
        ) async throws(DebugDrawerTransportError) -> UInt16

        /// Stops listening and advertising. Connections already accepted stay.
        func cancel()
    }
#endif
