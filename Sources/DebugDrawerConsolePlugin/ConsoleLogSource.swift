#if DEBUG
    /// Which lines the console shows: the ones captured since the app launched, or the ones an
    /// earlier launch kept on disk.
    enum ConsoleLogSource: Hashable, CaseIterable, Sendable {
        case captured
        case previous

        /// The segment's title.
        var title: String {
            switch self {
            case .captured: "Captured"
            case .previous: "Previous"
            }
        }
    }
#endif
