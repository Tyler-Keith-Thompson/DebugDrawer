#if DEBUG
    import Foundation

    /// The wall clock sessions open and expire by, and the audit log's entries are dated by.
    ///
    /// ``DebugDrawerSessions`` takes it at init; `_SessionClock` reads the system's, and a test
    /// passes one it moves by hand.
    protocol SessionClock {
        /// The time now.
        var now: Date { get }
    }
#endif
