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

    // MARK: - Sparkline

    struct Sparkline<T: BinaryFloatingPoint>: View {
        let data: [T]
        let color: Color
        let height: CGFloat

        var body: some View {
            Canvas { context, size in
                guard data.count > 1 else { return }
                let maxVal = data.max() ?? 1
                let minVal = data.min() ?? 0
                let range = maxVal - minVal
                let effectiveRange = range > 0 ? range : 1

                var path = Path()
                for (index, value) in data.enumerated() {
                    let normalized = CGFloat((value - minVal) / effectiveRange)
                    let point = CGPoint(
                        x: size.width * CGFloat(index) / CGFloat(data.count - 1),
                        y: size.height * (1 - normalized)
                    )
                    if index == 0 {
                        path.move(to: point)
                    } else {
                        path.addLine(to: point)
                    }
                }
                context.stroke(path, with: .color(color), lineWidth: 1.5)
            }
            .frame(height: height)
        }
    }

    struct IntSparkline: View {
        let data: [Int]
        let color: Color
        let height: CGFloat

        var body: some View {
            Sparkline(data: data.map(Double.init), color: color, height: height)
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
            VStack(alignment: .leading, spacing: 8) {
                // Start/stop
                Toggle("Monitor", isOn: Binding(
                    get: { monitor.isMonitoring },
                    set: { $0 ? monitor.start() : monitor.stop() }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)

                if monitor.isMonitoring {
                    PerformanceReadout(
                        fps: monitor.fps,
                        fpsHistory: monitor.fpsHistory,
                        footprintMB: monitor.footprintMB,
                        footprintHistory: monitor.footprintHistory
                    )
                }
            }
        }
    }

    /// The frame rate and memory now, their recent history as sparklines, and the minimum and
    /// average frame rate and peak memory.
    struct PerformanceReadout: View {
        let fps: Int
        /// Frames per second, one sample a second, oldest first.
        let fpsHistory: [Int]
        let footprintMB: Double
        /// The memory footprint in megabytes, one sample a second, oldest first.
        let footprintHistory: [Double]

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                // FPS
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("FPS")
                            .font(.caption.weight(.medium))
                        Spacer()
                        Text("\(fps)")
                            .font(.system(.title3, design: .monospaced, weight: .bold))
                            .foregroundStyle(fpsColor)
                    }
                    if fpsHistory.count > 1 {
                        IntSparkline(data: fpsHistory, color: fpsColor, height: 30)
                            .background(Color.primary.opacity(0.03))
                            .cornerRadius(3)
                    }
                }

                // Memory
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Footprint")
                            .font(.caption.weight(.medium))
                        Spacer()
                        Text(String(format: "%.1f MB", footprintMB))
                            .font(.system(.callout, design: .monospaced, weight: .medium))
                    }
                    if footprintHistory.count > 1 {
                        Sparkline(data: footprintHistory, color: .blue, height: 30)
                            .background(Color.primary.opacity(0.03))
                            .cornerRadius(3)
                    }
                }

                // Stats
                HStack(spacing: 12) {
                    statBadge("Min", "\(fpsHistory.min() ?? 0)", fpsColor)
                    statBadge("Avg", "\(fpsHistory.isEmpty ? 0 : fpsHistory.reduce(0, +) / fpsHistory.count)", fpsColor)
                    statBadge("Peak", String(format: "%.0f", footprintHistory.max() ?? 0), .blue)
                }
            }
        }

        private var fpsColor: Color {
            if fps >= 55 { return .green }
            if fps >= 30 { return .yellow }
            return .red
        }

        private func statBadge(_ label: String, _ value: String, _ color: Color) -> some View {
            VStack(spacing: 1) {
                Text(value)
                    .font(.system(.caption2, design: .monospaced, weight: .bold))
                    .foregroundStyle(color)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
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
