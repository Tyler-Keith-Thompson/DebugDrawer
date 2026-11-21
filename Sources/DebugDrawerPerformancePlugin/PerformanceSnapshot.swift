import Foundation

// Public because it is `PerformanceModel`'s `Snapshot`, and opaque: its fields stay internal, so a
// reader outside the module carries it whole, encoded. It holds the readings as numbers and the
// history as samples, oldest first; the gauges' colors, the sparklines, the lowest and average
// frame rate and every unit are the view's.

#if DEBUG
    /// Everything the Performance plugin shows, as a value: the frame rate and frames dropped, the
    /// memory footprint and its peak against the device's memory, each second's frame rate and
    /// footprint over the last `historyLength` seconds, the process's threads by CPU, and when a
    /// memory warning was last posted.
    ///
    /// ``PerformanceModel`` makes it; the plugin's view and its HUD readout draw it. It is
    /// `Codable`, so a transport can carry it.
    public struct PerformanceSnapshot: Codable, Equatable, Sendable {
        /// Whether the model is sampling: while at least one drawer shows the numbers.
        var isMonitoring = false
        /// Frames per second over the last second.
        var fps = 0
        /// The display link's frame rate, which a smooth frame rate reaches.
        var maximumFPS = 60
        /// The frames dropped while sampling, since the history was last dropped.
        var droppedFrames = 0
        /// Frames per second, one sample a second, oldest first.
        var fpsHistory: [Int] = []
        /// The memory footprint now, in megabytes (MiB).
        var footprintMB: Double = 0
        /// The memory footprint in megabytes, one sample a second, oldest first.
        var footprintHistory: [Double] = []
        /// The highest footprint since the process started, in megabytes (MiB).
        var peakFootprintMB: Double = 0
        /// The device's physical memory, in megabytes (MiB).
        var physicalMemoryMB: Double = 0
        /// How many seconds of samples the history keeps.
        var historyLength = PerformanceSnapshot.defaultHistoryLength
        /// The process's threads, busiest first, sampled with the rest each second.
        var threads: [ThreadCPU] = []
        /// When the memory warning was last posted, or `nil` for not yet.
        var memoryWarningPostedAt: Date?

        /// The history a model keeps until told otherwise: a minute.
        static let defaultHistoryLength = 60
    }
#else
    /// Release builds sample nothing: this stand-in holds nothing.
    public struct PerformanceSnapshot: Codable, Equatable, Sendable {}
#endif
