#if DEBUG
    /// Where the last send stands.
    enum SendState: Equatable, Sendable {
        case idle
        case sending
        /// Added under `identifier`, to be delivered after `delay`.
        case sent(identifier: String, delay: SendDelay)
        /// The system refused it, for this reason.
        case failed(message: String)
    }
#endif
