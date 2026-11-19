import DebugDrawer
import SwiftUI

/// Performance's HUD readout: the frame rate and memory now. Performance samples while a drawer's
/// HUD shows it.
///
/// The type exists in every build; in release it draws nothing and monitors nothing.
public struct PerformanceHUD: View {
    #if DEBUG
        @ObservedObject var monitor = PerformanceMonitor.shared
    #endif

    public var body: some View {
        #if DEBUG
            PerformanceHUDReadout(fps: monitor.fps, maximumFPS: monitor.maximumFPS, footprintMB: monitor.footprintMB)
        #else
            EmptyView()
        #endif
    }
}

#if DEBUG
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
