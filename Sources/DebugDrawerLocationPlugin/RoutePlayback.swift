#if DEBUG
    /// Where playback of a route stands.
    enum RoutePlayback: Codable, Equatable, Sendable {
        /// Not started, or stopped: no point delivered.
        case stopped
        /// Delivering, with this many points delivered so far.
        case playing(delivered: Int)
        /// Paused after this many points.
        case paused(delivered: Int)
        /// Every point delivered; the last one stays in effect until Stop.
        case finished

        /// How many of the route's `count` points have been delivered.
        func delivered(of count: Int) -> Int {
            switch self {
            case .stopped: 0
            case let .playing(delivered), let .paused(delivered): delivered
            case .finished: count
            }
        }
    }

    /// How much faster than the track's own times a route plays.
    enum PlaybackSpeed: Double, CaseIterable, Codable, Identifiable, Sendable {
        case times1 = 1
        case times2 = 2
        case times5 = 5
        case times10 = 10

        var id: Self { self }

        /// The speed menu's name for it ("2x").
        var title: String { "\(Int(rawValue))x" }
    }
#endif
