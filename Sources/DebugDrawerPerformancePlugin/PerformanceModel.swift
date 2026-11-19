import Combine
import DebugDrawer
import Foundation

#if DEBUG
    // The system work stays behind plain protocols with real defaults, each in its own file:
    // `PerformanceSampler` (the display link and the 1 s timer, `DisplayLinkSampler`), which is
    // also the model's clock; `ThreadSampler` (Mach's threads, `MachThreadSampler`);
    // `TaskVMInfoSource` (the kernel's footprint, `_TaskVMInfoSource`); and `MemoryWarningPoster`
    // (UIKit's notification, `MemoryWarningSimulator`). The model holds numbers only, and sets its
    // snapshot once per frame second, so a view redraws once a tick.

    /// The Performance plugin's state and behavior, without its views: the frame rate, frames
    /// dropped, memory and threads, sampled while a drawer shows them, read as a
    /// ``PerformanceSnapshot`` and changed with a ``PerformanceCommand``.
    ///
    /// Each drawer showing the plugin's view or HUD readout counts as a viewer, through the
    /// plugin's `didBecomeVisible(in:)` and `didBecomeHidden(in:)`; sampling runs from the first
    /// viewer to the last, so neither the display link nor the timer runs while nothing shows the
    /// plugin. Nothing is recorded from launch: the peak footprint is the kernel's lifetime peak,
    /// so it misses nothing while hidden, and the history keeps its last samples and carries on
    /// from them when the plugin is shown again.
    ///
    /// The plugin's view reaches it through a `DebugDrawerPluginTransport`:
    ///
    /// ```swift
    /// let transport = DebugDrawerPluginTransport.direct(to: PerformanceModel.shared)
    /// ```
    ///
    /// Release builds get a stand-in whose snapshot holds nothing and which ignores every command.
    @MainActor
    public final class PerformanceModel: DebugDrawerPluginModel {
        /// The model the plugin shows and samples with, made the first time something reads it.
        public static let shared = PerformanceModel()

        @Published public private(set) var snapshot: PerformanceSnapshot

        private let sampler: any PerformanceSampler
        private let threadSampler: any ThreadSampler
        private let memory: any TaskVMInfoSource
        private let memoryWarning: (any MemoryWarningPoster)?
        /// The drawers showing the numbers, and readers that sent `start`.
        private var viewers = 0
        /// The drawers the plugin is installed in; the last to remove it drops the history.
        private var installations: Set<ObjectIdentifier> = []
        /// The frames' timestamps since the last tick.
        private var frameTimestamps: [TimeInterval] = []
        /// The last frame of the tick before, which starts this tick's first gap.
        private var previousFrame: TimeInterval?
        private var frameDuration: TimeInterval = 1.0 / 60

        private convenience init() {
            // The model is made on the main actor, so this is the main thread's ID.
            self.init(
                sampler: DisplayLinkSampler(),
                threadSampler: MachThreadSampler(mainThreadID: MachThreadSampler.currentThreadID())
            )
        }

        /// A model that samples nothing until a viewer is counted.
        ///
        /// - Parameters:
        ///   - sampler: Calls back per frame and once a second while sampling.
        ///   - threadSampler: Reads the process's threads.
        ///   - memory: Reads the process's footprint.
        ///   - physicalMemory: The device's memory, in bytes.
        ///   - memoryWarning: Posts the memory warning, or `nil` where the platform has none.
        init(
            sampler: any PerformanceSampler,
            threadSampler: any ThreadSampler,
            memory: any TaskVMInfoSource = _TaskVMInfoSource(),
            physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory,
            memoryWarning: (any MemoryWarningPoster)? = PerformanceModel.systemMemoryWarning
        ) {
            self.sampler = sampler
            self.threadSampler = threadSampler
            self.memory = memory
            self.memoryWarning = memoryWarning
            snapshot = PerformanceSnapshot(physicalMemoryMB: Double(physicalMemory) / (1024 * 1024))
        }

        public func perform(_ command: PerformanceCommand) {
            switch command.action {
            case .start: addViewer()
            case .stop: removeViewer()
            case .reset: dropHistory()
            case let .setHistoryLength(length): setHistoryLength(length)
            case .simulateMemoryWarning: postMemoryWarning()
            }
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
            frameTimestamps = []
            previousFrame = nil
            snapshot = PerformanceSnapshot(
                maximumFPS: snapshot.maximumFPS,
                physicalMemoryMB: snapshot.physicalMemoryMB,
                historyLength: snapshot.historyLength
            )
        }

        private func start() {
            // The time nothing sampled is no gap between frames.
            previousFrame = nil
            frameTimestamps = []
            sampler.start(
                frame: { [weak self] timestamp, duration in self?.recordFrame(at: timestamp, duration: duration) },
                tick: { [weak self] in self?.sample() }
            )
            var next = snapshot
            next.isMonitoring = true
            readMemoryAndThreads(into: &next)
            snapshot = next
        }

        private func stop() {
            snapshot.isMonitoring = false
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

            var next = snapshot
            next.fps = statistics.framesPerSecond
            next.droppedFrames += statistics.droppedFrames
            next.maximumFPS = Int((1 / frameDuration).rounded())
            next.fpsHistory.append(next.fps, keepingLast: next.historyLength)
            readMemoryAndThreads(into: &next)
            next.footprintHistory.append(next.footprintMB, keepingLast: next.historyLength)
            snapshot = next
        }

        private func readMemoryAndThreads(into next: inout PerformanceSnapshot) {
            let footprint = MemoryFootprint.current(from: memory)
            next.footprintMB = footprint.megabytes
            next.peakFootprintMB = footprint.peakMegabytes
            next.threads = threadSampler.sample()
        }

        private func dropHistory() {
            var next = snapshot
            next.fpsHistory = []
            next.footprintHistory = []
            next.droppedFrames = 0
            snapshot = next
        }

        private func setHistoryLength(_ length: Int) {
            var next = snapshot
            next.historyLength = max(length, 1)
            next.fpsHistory = Array(next.fpsHistory.suffix(next.historyLength))
            next.footprintHistory = Array(next.footprintHistory.suffix(next.historyLength))
            snapshot = next
        }

        private func postMemoryWarning() {
            guard let memoryWarning else { return }
            snapshot.memoryWarningPostedAt = memoryWarning.postMemoryWarning()
        }

        /// The platform's memory warning: UIKit's notification, and none on the Mac, which has no
        /// public way to simulate memory pressure.
        static var systemMemoryWarning: (any MemoryWarningPoster)? {
            #if os(iOS) || os(tvOS) || os(visionOS)
                MemoryWarningSimulator()
            #else
                nil
            #endif
        }
    }

    extension Array {
        /// Appends `element`, then drops the oldest elements beyond the last `limit`.
        fileprivate mutating func append(_ element: Element, keepingLast limit: Int) {
            append(element)
            if count > limit { removeFirst(count - limit) }
        }
    }
#else
    // The release stand-in: the same members, and nothing behind them.

    /// Release builds sample nothing: this stand-in's snapshot holds nothing, and it ignores every
    /// command.
    @MainActor
    public final class PerformanceModel: DebugDrawerPluginModel {
        /// The stand-in model.
        public static let shared = PerformanceModel()

        private init() {}

        /// Always empty.
        public var snapshot: PerformanceSnapshot {
            PerformanceSnapshot()
        }

        /// Does nothing.
        ///
        /// - Parameter command: Ignored.
        public func perform(_ command: PerformanceCommand) {}
    }
#endif
