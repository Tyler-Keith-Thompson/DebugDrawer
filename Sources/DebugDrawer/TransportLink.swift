#if DEBUG
    /// What carries a connection's messages, which decides how its two sides meet.
    package enum TransportLink: Sendable {
        /// A stream both sides read and write in order (the socket, a network connection): each
        /// side says hello as it connects, and a viewer asks for each plugin it shows.
        case stream
        /// The app-group store's files: no one to greet, so each document names the build that
        /// wrote it, and the app writes every plugin's snapshots unasked.
        case store
    }
#endif
