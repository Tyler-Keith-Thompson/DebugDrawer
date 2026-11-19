import DebugDrawer
import SwiftUI

// MARK: - Plugin

// The public API compiles in every configuration; the implementation under `#if DEBUG` below does
// not, so release builds get an empty view and an installer that samples and registers nothing.

/// The frame rate, dropped frames, memory footprint with its peak and CPU use per thread, as
/// they change.
public struct PerformancePlugin: DebugDrawerPlugin {
    /// The plugin's identity in the drawer, which its saved state, HUD pin and badges are kept under.
    public var id: String {
        "PerformancePlugin"
    }

    public var title = "Performance"
    public var category = "Performance"
    public var icon = "gauge.with.dots.needle.33percent"

    #if DEBUG
        /// The monitor the plugin shows and samples with, or `nil` for ``PerformanceMonitor/shared``,
        /// which is made only once something reads it.
        private let monitor: PerformanceMonitor?

        public init() {
            monitor = nil
        }

        /// - Parameter monitor: The monitor to show and sample with in place of the shared one.
        init(monitor: PerformanceMonitor) {
            self.monitor = monitor
        }
    #else
        public init() {}
    #endif

    public var body: some View {
        #if DEBUG
            PerformancePluginView(monitor: monitor ?? .shared)
        #else
            EmptyView()
        #endif
    }

    /// The frame rate and memory, for the floating HUD; none in release builds.
    public var hud: PerformanceHUD? {
        #if DEBUG
            PerformanceHUD(monitor: monitor ?? .shared)
        #else
            nil
        #endif
    }

    /// Starts sampling the frame rate, memory and threads: the plugin's view or its HUD readout is
    /// on screen in `drawer`. Release builds sample nothing.
    @MainActor public func didBecomeVisible(in drawer: DebugDrawer) {
        #if DEBUG
            (monitor ?? .shared).addViewer()
        #endif
    }

    /// Stops the sampling ``didBecomeVisible(in:)`` started, once no drawer shows the plugin.
    @MainActor public func didBecomeHidden(in drawer: DebugDrawer) {
        #if DEBUG
            (monitor ?? .shared).removeViewer()
        #endif
    }

    /// Counts `drawer` as one that holds the plugin; nothing is sampled until it is shown.
    @MainActor public func install(in drawer: DebugDrawer) {
        #if DEBUG
            (monitor ?? .shared).install(in: ObjectIdentifier(drawer))
        #endif
    }

    /// Once the last drawer that held the plugin removes it, stops any sampling still running and
    /// drops the frame, memory and thread history, so a later install starts from nothing.
    @MainActor public func uninstall(from drawer: DebugDrawer) {
        #if DEBUG
            (monitor ?? .shared).uninstall(from: ObjectIdentifier(drawer))
        #endif
    }
}

// MARK: - Convenience installer

public extension DebugDrawer {
    /// Registers the Performance plugin. It samples only while its view or its HUD readout is on
    /// screen.
    func installPerformance() {
        #if DEBUG
            registerGlobal(PerformancePlugin())
        #endif
    }
}

#if DEBUG
    // MARK: - Performance metrics

    /// The frame rate, memory and threads, sampled while a drawer shows them: the plugin's view or
    /// its HUD readout. Each drawer showing the plugin adds a viewer through
    /// ``PerformancePlugin/didBecomeVisible(in:)`` and removes it through
    /// ``PerformancePlugin/didBecomeHidden(in:)``; sampling runs from the first viewer to the
    /// last, so neither the display link nor the timer runs while no drawer shows the plugin.
    ///
    /// Nothing is recorded from launch: the peak footprint is the kernel's lifetime peak, so it
    /// misses nothing while hidden, and the frame and memory history keep their last samples
    /// and carry on from them when the plugin is shown again.
    @MainActor
    final class PerformanceMonitor: ObservableObject {
        static let shared = PerformanceMonitor()

        /// Frames per second over the last second.
        @Published private(set) var fps: Int = 0
        /// The frames dropped while sampling, over the monitor's life.
        @Published private(set) var droppedFrames = 0
        @Published private(set) var footprintMB: Double = 0
        /// The highest footprint since the process started, in megabytes.
        @Published private(set) var peakFootprintMB: Double = 0
        @Published private(set) var footprintHistory: [Double] = []
        @Published private(set) var fpsHistory: [Int] = []
        /// Whether the sampler is running: while at least one drawer shows the numbers.
        @Published private(set) var isMonitoring = false
        /// The display link's frame rate, which a smooth frame rate reaches.
        @Published private(set) var maximumFPS = 60
        /// The process's threads, busiest first, sampled with the rest each second.
        @Published private(set) var threads: [ThreadCPU] = []

        private let sampler: any PerformanceSampler
        private let threadSampler: any ThreadSampler
        private var viewers = 0
        /// The drawers the plugin is installed in; the last to remove it drops the history.
        private var installations: Set<ObjectIdentifier> = []
        /// The frames' timestamps since the last tick.
        private var frameTimestamps: [TimeInterval] = []
        /// The last frame of the tick before, which starts this tick's first gap.
        private var previousFrame: TimeInterval?
        private var frameDuration: TimeInterval = 1.0 / 60
        private let historySize = 60

        private convenience init() {
            // The monitor is made on the main actor, so this is the main thread's ID.
            self.init(
                sampler: DisplayLinkSampler(),
                threadSampler: MachThreadSampler(mainThreadID: MachThreadSampler.currentThreadID())
            )
        }

        init(sampler: any PerformanceSampler, threadSampler: any ThreadSampler) {
            self.sampler = sampler
            self.threadSampler = threadSampler
        }

        /// Counts a drawer that shows the numbers; the first one starts sampling.
        func addViewer() {
            viewers += 1
            if viewers == 1 { start() }
        }

        /// Uncounts a drawer that showed the numbers; the last one stops sampling.
        func removeViewer() {
            guard viewers > 0 else { return }
            viewers -= 1
            if viewers == 0 { stop() }
        }

        /// Counts `drawer` as one the plugin is installed in.
        func install(in drawer: ObjectIdentifier) {
            installations.insert(drawer)
        }

        /// Uncounts `drawer`; once no drawer holds the plugin, stops sampling should a drawer still
        /// count as showing it, and drops every reading and its history.
        func uninstall(from drawer: ObjectIdentifier) {
            guard installations.remove(drawer) != nil, installations.isEmpty else { return }
            if viewers > 0 {
                viewers = 0
                stop()
            }
            fps = 0
            droppedFrames = 0
            footprintMB = 0
            peakFootprintMB = 0
            footprintHistory = []
            fpsHistory = []
            threads = []
            frameTimestamps = []
            previousFrame = nil
        }

        /// The device's physical memory, in megabytes (MiB).
        static var physicalMemoryMB: Double {
            Double(ProcessInfo.processInfo.physicalMemory) / (1024 * 1024)
        }

        private func start() {
            isMonitoring = true
            // The time nothing sampled is no gap between frames.
            previousFrame = nil
            frameTimestamps = []
            sampler.start(
                frame: { [weak self] timestamp, duration in self?.recordFrame(at: timestamp, duration: duration) },
                tick: { [weak self] in self?.sample() }
            )
            sampleMemoryAndThreads()
        }

        private func stop() {
            isMonitoring = false
            sampler.stop()
        }

        private func recordFrame(at timestamp: TimeInterval, duration: TimeInterval) {
            frameTimestamps.append(timestamp)
            if duration > 0 { frameDuration = duration }
        }

        private func sample() {
            let window = (previousFrame.map { [$0] } ?? []) + frameTimestamps
            let statistics = FrameStatistics(timestamps: window, frameDuration: frameDuration)
            previousFrame = window.last
            frameTimestamps.removeAll(keepingCapacity: true)
            fps = statistics.framesPerSecond
            droppedFrames += statistics.droppedFrames
            maximumFPS = Int((1 / frameDuration).rounded())
            fpsHistory.append(fps)
            if fpsHistory.count > historySize { fpsHistory.removeFirst() }

            sampleMemoryAndThreads()
            footprintHistory.append(footprintMB)
            if footprintHistory.count > historySize { footprintHistory.removeFirst() }
        }

        private func sampleMemoryAndThreads() {
            let footprint = MemoryFootprint.current()
            footprintMB = footprint.megabytes
            peakFootprintMB = footprint.peakMegabytes
            threads = threadSampler.sample()
        }
    }

    /// The monitor's numbers. Showing it samples nothing by itself: the drawer that shows it
    /// starts the monitor through the plugin's lifecycle hooks.
    struct PerformancePluginView: View {
        @ObservedObject var monitor = PerformanceMonitor.shared

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                PerformanceReadout(
                    fps: monitor.fps,
                    fpsHistory: monitor.fpsHistory,
                    maximumFPS: monitor.maximumFPS,
                    droppedFrames: monitor.droppedFrames,
                    footprintMB: monitor.footprintMB,
                    footprintHistory: monitor.footprintHistory,
                    peakFootprintMB: monitor.peakFootprintMB,
                    physicalMemoryMB: PerformanceMonitor.physicalMemoryMB
                )
                ThreadsSection(threads: monitor.threads)
                // UIKit's platforms only: the Mac has no public way to simulate memory pressure.
                #if os(iOS) || os(tvOS) || os(visionOS)
                    MemoryWarningSection { MemoryWarningSimulator().post() }
                #endif
            }
        }
    }

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
