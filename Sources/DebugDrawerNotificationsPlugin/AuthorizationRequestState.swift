#if DEBUG
    /// Where asking for authorization stands.
    enum AuthorizationRequestState: Equatable, Sendable {
        case idle
        /// The system's prompt is up.
        case requesting
        /// The system couldn't ask, for this reason.
        case failed(message: String)
    }
#endif
