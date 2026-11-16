#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// Performance's HUD readout: the frame rate and memory now. It monitors while it is on screen
    /// if nothing else started monitoring.
    public struct PerformanceHUD: View {
        @ObservedObject private var monitor = PerformanceMonitor.shared
        @State private var startedMonitoring = false

        public var body: some View {
            PerformanceHUDReadout(fps: monitor.fps, maximumFPS: monitor.maximumFPS, footprintMB: monitor.footprintMB)
                .onAppear {
                    guard !monitor.isMonitoring else { return }
                    monitor.start()
                    startedMonitoring = true
                }
                .onDisappear {
                    guard startedMonitoring else { return }
                    monitor.stop()
                    startedMonitoring = false
                }
        }
    }

    /// The frame rate, with an issue glyph while frames drop, and the memory footprint, on one
    /// line.
    struct PerformanceHUDReadout: View {
        let fps: Int
        var maximumFPS = 60
        let footprintMB: Double

        var body: some View {
            HStack(spacing: 10) {
                if let severity = FrameRate.severity(fps: fps, maximum: maximumFPS) {
                    DebugDrawerIssueGlyph(severity)
                        .accessibilityLabel(severity == .error ? "Frames dropping badly" : "Frames dropping")
                }
                Text("\(fps) FPS")
                Text("\(Text(footprintMB, format: .number.precision(.fractionLength(0)))) MB")
            }
            .debugDrawerFont(.value)
            .accessibilityElement(children: .combine)
        }
    }
#endif
