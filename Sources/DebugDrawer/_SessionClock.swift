#if DEBUG
    import Foundation

    /// The system's wall clock.
    struct _SessionClock: SessionClock {
        var now: Date {
            Date()
        }
    }
#endif
