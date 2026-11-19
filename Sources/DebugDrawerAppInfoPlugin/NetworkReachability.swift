#if DEBUG
    /// How the app reaches the network, by the interface its path uses; its word is the view's.
    enum NetworkReachability: String, Codable, Equatable, Sendable {
        /// Not watched yet, or no longer.
        case unknown
        /// No path is satisfied.
        case offline
        case wifi
        case cellular
        case wiredEthernet
        /// A path through another interface, such as a VPN or loopback.
        case online
    }
#endif
