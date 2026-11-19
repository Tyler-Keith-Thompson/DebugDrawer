import Foundation

// Public because it is `DiskIOModel`'s `Snapshot`, and opaque: its fields stay internal, so the
// plugin's own types (a volume's figures) don't become API. A reader outside the module carries it
// whole, encoded. It holds the calls kept and the filter; which calls the list shows is worked out
// from them, and the view formats all of it.

#if DEBUG
    /// Everything the Disk I/O plugin shows, as a value: the recorded calls and their totals, the
    /// filter, whether recording is paused, and the volume's size and free space.
    ///
    /// ``DiskIOModel`` makes it; the plugin's view draws it. It is `Codable`, so a transport can
    /// carry it.
    public struct DiskIOSnapshot: Codable, Equatable, Sendable {
        /// The kept calls, newest first.
        var events: [IOEvent] = []
        /// Every call since the last clear, including the ones ``events`` no longer keeps.
        var totals = DiskIOTotals()
        /// The operation the list shows alone, or `nil` for every operation.
        var operation: IOEvent.Operation?
        /// Whether the list shows only the calls made on the main thread.
        var mainThreadOnly = false
        /// Whether recording is paused.
        var isPaused = false
        /// The home directory's volume, or `nil` until it is read or when the system won't say.
        var volume: DiskSpace?

        /// The kept calls that pass ``operation`` and ``mainThreadOnly``, newest first.
        var filteredEvents: [IOEvent] {
            var result = events
            if let operation { result = result.filter { $0.operation == operation } }
            if mainThreadOnly { result = result.filter(\.isMainThread) }
            return result
        }
    }
#else
    /// Release builds record no disk I/O: this stand-in holds nothing.
    public struct DiskIOSnapshot: Codable, Equatable, Sendable {}
#endif
