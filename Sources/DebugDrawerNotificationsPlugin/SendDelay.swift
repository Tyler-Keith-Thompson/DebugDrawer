#if DEBUG
    /// When a sent payload is delivered: at once, or after a few seconds, long enough to put the
    /// app in the background and see the banner the system shows there.
    enum SendDelay: Equatable, Hashable, Sendable, CaseIterable, Identifiable {
        case now
        case fiveSeconds
        case thirtySeconds

        var id: Self {
            self
        }

        /// The delay in seconds; `nil` delivers at once, with no trigger.
        var seconds: Double? {
            switch self {
            case .now: nil
            case .fiveSeconds: 5
            case .thirtySeconds: 30
            }
        }

        var title: String {
            switch self {
            case .now: "Now"
            case .fiveSeconds: "In 5 sec"
            case .thirtySeconds: "In 30 sec"
            }
        }
    }
#endif
