#if DEBUG
    /// What came of the last send. The view words it (`DeepLinkOutcome+Text.swift`).
    enum DeepLinkOutcome: Hashable, Codable, Sendable {
        /// The `openURL` handler took the URL.
        case handled(String)
        /// The `openURL` handler returned false for the URL.
        case notHandled(String)
        /// The system opened the URL.
        case opened(String)
        /// The system couldn't open the URL, for the reason given.
        case couldNotOpen(String, reason: String)
        /// An activity went where the delivery says.
        case continued(UserActivityDelivery)
    }
#endif
