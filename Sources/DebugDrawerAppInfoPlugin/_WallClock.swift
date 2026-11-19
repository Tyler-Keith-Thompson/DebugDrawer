#if DEBUG
    import Foundation

    /// The system's wall clock.
    struct _WallClock: WallClock {
        var now: Date {
            Date()
        }
    }
#endif
