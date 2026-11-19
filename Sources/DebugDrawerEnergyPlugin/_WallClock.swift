#if DEBUG
    import Foundation

    /// The system's time of day.
    struct _WallClock: WallClock {
        var now: Date {
            Date()
        }
    }
#endif
