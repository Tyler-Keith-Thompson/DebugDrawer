#if DEBUG
    #if os(macOS)
        import AppKit
    #elseif os(iOS)
        import UIKit
    #endif
    import Combine
    import DebugDrawer
    import QuartzCore
    import SwiftUI

    // MARK: - Performance metrics

    @MainActor
    final class PerformanceMonitor: ObservableObject {
        static let shared = PerformanceMonitor()

        @Published var fps: Int = 0
        @Published var footprintMB: Double = 0
        @Published var footprintHistory: [Double] = []
        @Published var fpsHistory: [Int] = []
        @Published var isMonitoring = false
        /// The display's highest refresh rate, read when monitoring starts.
        @Published var maximumFPS = 60

        private var displayLink: CADisplayLink?
        private var frameCount = 0
        private var lastFPSTime: CFTimeInterval = 0
        private var cancellable: AnyCancellable?
        private let historySize = 60

        private init() {}

        func start() {
            guard !isMonitoring else { return }
            isMonitoring = true

            // Memory + FPS history sampled every second via Timer
            cancellable = Timer.publish(every: 1, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in self?.sample() }

            // FPS: a display link on the main run loop, so frameCount is only touched on the main actor.
            #if os(macOS)
                guard let screen = NSScreen.main else { return }
                let link = screen.displayLink(target: self, selector: #selector(displayLinkFired))
            #else
                let link = CADisplayLink(target: self, selector: #selector(displayLinkFired))
            #endif
            maximumFPS = Self.displayMaximumFPS ?? maximumFPS
            link.add(to: .main, forMode: .common)
            displayLink = link
            lastFPSTime = CACurrentMediaTime()
        }

        func stop() {
            guard isMonitoring else { return }
            isMonitoring = false
            cancellable?.cancel()
            cancellable = nil
            displayLink?.invalidate()
            displayLink = nil
        }

        /// The device's physical memory, in megabytes (MiB).
        static var physicalMemoryMB: Double {
            Double(ProcessInfo.processInfo.physicalMemory) / (1024 * 1024)
        }

        /// The highest refresh rate of the app's displays, or `nil` when none is on screen.
        private static var displayMaximumFPS: Int? {
            #if os(macOS)
                NSScreen.main?.maximumFramesPerSecond
            #else
                UIApplication.shared.connectedScenes
                    .compactMap { ($0 as? UIWindowScene)?.screen.maximumFramesPerSecond }
                    .max()
            #endif
        }

        @objc private func displayLinkFired() {
            frameCount += 1
        }

        private func sample() {
            // FPS
            let now = CACurrentMediaTime()
            let elapsed = now - lastFPSTime
            if elapsed > 0 {
                fps = Int(Double(frameCount) / elapsed)
            }
            frameCount = 0
            lastFPSTime = now

            fpsHistory.append(fps)
            if fpsHistory.count > historySize { fpsHistory.removeFirst() }

            // Memory
            footprintMB = MemoryFootprint.currentMB()
            footprintHistory.append(footprintMB)
            if footprintHistory.count > historySize { footprintHistory.removeFirst() }
        }
    }

    // MARK: - Plugin

    public struct PerformancePlugin: DebugDrawerPlugin {
        public var title = "Performance"
        public var category = "Performance"
        public var icon = "gauge.with.dots.needle.33percent"

        public init() {}

        public var body: some View {
            PerformancePluginView()
        }

        /// The frame rate and memory, for the floating HUD.
        public var hud: PerformanceHUD? {
            PerformanceHUD()
        }
    }

    struct PerformancePluginView: View {
        @ObservedObject private var monitor = PerformanceMonitor.shared

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                DebugDrawerRow("Monitor", isOn: Binding(
                    get: { monitor.isMonitoring },
                    set: { $0 ? monitor.start() : monitor.stop() }
                ))
                if monitor.isMonitoring {
                    PerformanceReadout(
                        fps: monitor.fps,
                        fpsHistory: monitor.fpsHistory,
                        maximumFPS: monitor.maximumFPS,
                        footprintMB: monitor.footprintMB,
                        footprintHistory: monitor.footprintHistory,
                        physicalMemoryMB: PerformanceMonitor.physicalMemoryMB
                    )
                }
            }
        }
    }

    /// The frame rate against the display's refresh rate and the memory footprint against the
    /// device's memory, as gauges, their recent history as sparklines, and the lowest and average
    /// frame rate and the peak footprint.
    struct PerformanceReadout: View {
        let fps: Int
        /// Frames per second, one sample a second, oldest first.
        let fpsHistory: [Int]
        /// The display's highest refresh rate, which a smooth frame rate reaches.
        let maximumFPS: Int
        let footprintMB: Double
        /// The memory footprint in megabytes, one sample a second, oldest first.
        let footprintHistory: [Double]
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
                }
                DebugDrawerSection("Memory") {
                    DebugDrawerGaugeRow(
                        "Footprint",
                        value: "\(footprintMB.formatted(.number.precision(.fractionLength(1)))) MB",
                        fraction: memoryFraction,
                        severity: memoryFraction >= 0.5 ? .warning : nil
                    )
                    DebugDrawerSparkline("Footprint history", data: footprintHistory)
                    DebugDrawerKeyValueRow("Peak", value: "\((footprintHistory.max() ?? 0).formatted(.number.precision(.fractionLength(0)))) MB")
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

    // MARK: - Convenience installer

    public extension DebugDrawer {
        func installPerformance() {
            PerformanceMonitor.shared.start()
            registerGlobal(PerformancePlugin())
        }
    }
#endif
