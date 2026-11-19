#if DEBUG
    import Foundation

    /// Where App Info reads this process: its start, its memory footprint, its ID and its
    /// arguments.
    ///
    /// The App Info model takes it at init; `_ProcessMetricsSource` asks the kernel and
    /// `ProcessInfo`, and a test passes one that returns what it chooses and counts its readings.
    protocol ProcessMetricsSource {
        /// When the process started and whether a debugger is attached, or `nil` when the kernel
        /// won't say.
        func start() -> ProcessStart?

        /// The memory footprint now, in megabytes (MiB), or 0 when the kernel won't report it.
        func footprintMB() -> Double

        /// The process's ID.
        var processIdentifier: Int32 { get }

        /// How many arguments the process was launched with, its path included.
        var argumentCount: Int { get }
    }
#endif
