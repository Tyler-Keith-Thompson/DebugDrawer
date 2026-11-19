#if DEBUG
    import Foundation

    /// When the app's process started, on the system's uptime timeline.
    ///
    /// The Launch Time model takes it at init; `_ProcessStartReader` asks the kernel, and a test
    /// passes one that returns a fixed time, or none.
    protocol ProcessStartReader {
        /// The system uptime when the process started, or `nil` when it can't be read.
        func processStartUptime() -> TimeInterval?
    }
#endif
