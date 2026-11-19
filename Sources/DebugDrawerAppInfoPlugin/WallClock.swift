#if DEBUG
    import Foundation

    /// The wall clock, which the uptime and the profile's expiry are measured against.
    ///
    /// The App Info model takes it at init; `_WallClock` reads the system's, and a test passes one
    /// it moves by hand.
    protocol WallClock {
        /// The time now.
        var now: Date { get }
    }
#endif
