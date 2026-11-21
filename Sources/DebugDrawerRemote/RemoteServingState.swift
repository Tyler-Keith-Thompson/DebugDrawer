#if DEBUG
    /// Where the Remote Viewing plugin's server is between not listening and listening.
    enum RemoteServingState: Equatable {
        /// Not listening, and not asked to.
        case stopped
        /// Asked to listen, and waiting for the system.
        case starting
        /// Listening on `port`, on 127.0.0.1 alone when `loopbackOnly`, advertised over Bonjour
        /// when `advertises`.
        case listening(port: UInt16, loopbackOnly: Bool, advertises: Bool)
        /// The last start failed, for the reason given.
        case failed(String)
    }
#endif
