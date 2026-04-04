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
        @Published var memoryMB: Double = 0
        @Published var memoryHistory: [Double] = []
        @Published var fpsHistory: [Int] = []
        @Published var isMonitoring = false

        #if os(macOS)
            private var displayLink: CVDisplayLink?
        #elseif os(iOS)
            private var displayLink: CADisplayLink?
        #endif
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

            #if os(macOS)
                // FPS via CVDisplayLink
                var link: CVDisplayLink?
                CVDisplayLinkCreateWithActiveCGDisplays(&link)
                guard let link else { return }
                displayLink = link

                let callback: CVDisplayLinkOutputCallback = { _, _, _, _, _, userInfo -> CVReturn in
                    let monitor = Unmanaged<PerformanceMonitor>.fromOpaque(userInfo!).takeUnretainedValue()
                    monitor.frameCount += 1
                    return kCVReturnSuccess
                }

                let selfPtr = Unmanaged.passUnretained(self).toOpaque()
                CVDisplayLinkSetOutputCallback(link, callback, selfPtr)
                CVDisplayLinkStart(link)
            #elseif os(iOS)
                // FPS via CADisplayLink
                let link = CADisplayLink(target: self, selector: #selector(displayLinkFired))
                link.add(to: .main, forMode: .common)
                displayLink = link
            #endif
            lastFPSTime = CACurrentMediaTime()
        }

        func stop() {
            guard isMonitoring else { return }
            isMonitoring = false
            cancellable?.cancel()
            cancellable = nil
            #if os(macOS)
                if let link = displayLink {
                    CVDisplayLinkStop(link)
                    displayLink = nil
                }
            #elseif os(iOS)
                displayLink?.invalidate()
                displayLink = nil
            #endif
        }

        #if os(iOS)
            @objc private func displayLinkFired() {
                frameCount += 1
            }
        #endif

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
            memoryMB = Self.currentMemoryMB()
            memoryHistory.append(memoryMB)
            if memoryHistory.count > historySize { memoryHistory.removeFirst() }
        }

        private static func currentMemoryMB() -> Double {
            var info = mach_task_basic_info()
            var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
            let result = withUnsafeMutablePointer(to: &info) { ptr in
                ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                    task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), intPtr, &count)
                }
            }
            guard result == KERN_SUCCESS else { return 0 }
            return Double(info.resident_size) / (1024 * 1024)
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
                for (i, val) in data.enumerated() {
                    let x = size.width * CGFloat(i) / CGFloat(data.count - 1)
                    let normalized = CGFloat((val - minVal) / effectiveRange)
                    let y = size.height * (1 - normalized)
                    if i == 0 { path.move(to: .init(x: x, y: y)) }
                    else { path.addLine(to: .init(x: x, y: y)) }
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
        public var icon = "gauge.with.dots.needle.33percent"

        public init() {}

        public var body: some View {
            PerformancePluginView()
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
                    // FPS
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("FPS")
                                .font(.caption.weight(.medium))
                            Spacer()
                            Text("\(monitor.fps)")
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundStyle(fpsColor)
                        }
                        if monitor.fpsHistory.count > 1 {
                            IntSparkline(data: monitor.fpsHistory, color: fpsColor, height: 30)
                                .background(Color.primary.opacity(0.03))
                                .cornerRadius(3)
                        }
                    }

                    // Memory
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Memory")
                                .font(.caption.weight(.medium))
                            Spacer()
                            Text(String(format: "%.1f MB", monitor.memoryMB))
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                        }
                        if monitor.memoryHistory.count > 1 {
                            Sparkline(data: monitor.memoryHistory, color: .blue, height: 30)
                                .background(Color.primary.opacity(0.03))
                                .cornerRadius(3)
                        }
                    }

                    // Stats
                    HStack(spacing: 12) {
                        statBadge("Min", "\(monitor.fpsHistory.min() ?? 0)", fpsColor)
                        statBadge("Avg", "\(monitor.fpsHistory.isEmpty ? 0 : monitor.fpsHistory.reduce(0, +) / monitor.fpsHistory.count)", fpsColor)
                        statBadge("Mem Peak", String(format: "%.0f", monitor.memoryHistory.max() ?? 0), .blue)
                    }
                }
            }
        }

        private var fpsColor: Color {
            if monitor.fps >= 55 { return .green }
            if monitor.fps >= 30 { return .yellow }
            return .red
        }

        private func statBadge(_ label: String, _ value: String, _ color: Color) -> some View {
            VStack(spacing: 1) {
                Text(value)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
                Text(label)
                    .font(.system(size: 8))
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
