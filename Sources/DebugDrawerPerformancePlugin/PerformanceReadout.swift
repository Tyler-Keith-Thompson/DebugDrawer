#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The frame rate against the display link's rate and the memory footprint against the
    /// device's memory, as gauges, their recent history as sparklines, the lowest and average
    /// frame rate, the frames dropped, and the peak footprint.
    struct PerformanceReadout: View {
        let fps: Int
        /// Frames per second, one sample a second, oldest first.
        let fpsHistory: [Int]
        /// The display link's frame rate, which a smooth frame rate reaches.
        let maximumFPS: Int
        /// The frames dropped while sampling.
        let droppedFrames: Int
        let footprintMB: Double
        /// The memory footprint in megabytes, one sample a second, oldest first.
        let footprintHistory: [Double]
        /// The highest footprint since the process started, in megabytes.
        let peakFootprintMB: Double
        /// The device's physical memory in megabytes.
        let physicalMemoryMB: Double

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                let frameSeverity = FrameRate.severity(fps: fps, maximum: maximumFPS)
                let memoryFraction = footprintMB / max(physicalMemoryMB, 1)
                DebugDrawerSection("Frames") {
                    DebugDrawerGaugeRow(
                        "FPS",
                        value: "\(fps) fps",
                        fraction: Double(fps) / Double(max(maximumFPS, 1)),
                        severity: frameSeverity
                    )
                    DebugDrawerSparkline("Frame rate history", data: fpsHistory.map(Double.init), severity: frameSeverity)
                    DebugDrawerKeyValueRow("Lowest", value: "\(fpsHistory.min() ?? 0) fps")
                    DebugDrawerKeyValueRow("Average", value: "\(averageFPS) fps")
                    // The section says what is dropped; "Dropped Frames" would wrap in the label column.
                    DebugDrawerKeyValueRow("Dropped", value: "\(droppedFrames)")
                }
                DebugDrawerSection("Memory") {
                    DebugDrawerGaugeRow(
                        "Footprint",
                        value: "\(footprintMB.formatted(.number.precision(.fractionLength(1)))) MB",
                        fraction: memoryFraction,
                        severity: memoryFraction >= 0.5 ? .warning : nil
                    )
                    DebugDrawerSparkline("Footprint history", data: footprintHistory)
                    DebugDrawerKeyValueRow("Peak", value: "\(peakFootprintMB.formatted(.number.precision(.fractionLength(0)))) MB")
                }
            }
        }

        private var averageFPS: Int {
            fpsHistory.isEmpty ? 0 : fpsHistory.reduce(0, +) / fpsHistory.count
        }
    }

    /// How smooth a frame rate is, against the display's highest.
    enum FrameRate {
        /// `nil` (the accent) at 90% of the display's rate or more, a warning from half of it,
        /// and an error below half.
        static func severity(fps: Int, maximum: Int) -> DebugDrawerIssueGlyph.Severity? {
            let fraction = Double(fps) / Double(max(maximum, 1))
            if fraction >= 0.9 { return nil }
            return fraction >= 0.5 ? .warning : .error
        }
    }
#endif
