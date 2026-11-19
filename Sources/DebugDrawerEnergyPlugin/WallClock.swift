#if DEBUG
    import Foundation

    /// The time of day, which each battery sample is stamped with.
    ///
    /// The Energy monitor takes it at init; `_WallClock` reads the system's, and a test passes one
    /// it moves by hand.
    protocol WallClock {
        /// The time now.
        var now: Date { get }
    }
#endif
