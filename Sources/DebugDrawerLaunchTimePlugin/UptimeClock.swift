#if DEBUG
    import Foundation

    /// The system's uptime: seconds since boot, the timeline every launch time is measured on.
    ///
    /// The Launch Time model takes it at init; `_UptimeClock` reads the system's, and a test
    /// passes one it moves by hand.
    protocol UptimeClock {
        /// Seconds since boot, now.
        var uptime: TimeInterval { get }
    }

    /// The system's uptime, from `ProcessInfo`.
    struct _UptimeClock: UptimeClock {
        var uptime: TimeInterval {
            ProcessInfo.processInfo.systemUptime
        }
    }
#endif
