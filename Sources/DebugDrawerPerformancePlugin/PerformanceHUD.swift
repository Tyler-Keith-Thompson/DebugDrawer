#if DEBUG
    import SwiftUI

    /// Performance's HUD readout: the frame rate and memory now. It monitors while it is on screen
    /// if nothing else started monitoring.
    public struct PerformanceHUD: View {
        @ObservedObject private var monitor = PerformanceMonitor.shared
        @State private var startedMonitoring = false

        public var body: some View {
            PerformanceHUDReadout(fps: monitor.fps, memoryMB: monitor.memoryMB)
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

    /// The frame rate, colored by how smooth it is, and resident memory, on one line.
    struct PerformanceHUDReadout: View {
        let fps: Int
        let memoryMB: Double

        var body: some View {
            HStack(spacing: 10) {
                Text("\(fps) FPS")
                    .foregroundStyle(fpsColor)
                Text(memoryMB, format: .number.precision(.fractionLength(0)))
                    + Text(" MB")
            }
            .font(.system(.caption, design: .monospaced, weight: .semibold))
            .monospacedDigit()
            .accessibilityElement(children: .combine)
        }

        private var fpsColor: Color {
            if fps >= 55 { return .green }
            if fps >= 30 { return .yellow }
            return .red
        }
    }
#endif
