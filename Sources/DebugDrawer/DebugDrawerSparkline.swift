import SwiftUI

/// A line graph of recent samples, oldest on the left, with no axes, on a faint panel. It draws
/// nothing until there are two samples to join.
///
/// VoiceOver reads its label, then the latest sample and the lowest and highest.
///
/// The type exists in every build so a plugin's body compiles unchanged in release, where it
/// draws nothing.
public struct DebugDrawerSparkline: View {
    let label: String
    let data: [Double]
    let range: ClosedRange<Double>?
    let color: Color
    let height: CGFloat

    /// - Parameters:
    ///   - label: What the samples are, for VoiceOver ("Frame rate history").
    ///   - data: The samples, oldest first.
    ///   - range: The values at the bottom and top of the graph; `nil` fits the graph to the
    ///     samples' lowest and highest.
    ///   - color: The line's color.
    ///   - height: The graph's height in points.
    public init(_ label: String, data: [Double], range: ClosedRange<Double>? = nil, color: Color, height: CGFloat = 30) {
        self.label = label
        self.data = data
        self.range = range
        self.color = color
        self.height = height
    }

    public var body: some View {
        #if DEBUG
            content
        #else
            EmptyView()
        #endif
    }
}

#if DEBUG
    extension DebugDrawerSparkline {
        @ViewBuilder
        private var content: some View {
            if let lowest = data.min(), let highest = data.max(), data.count > 1 {
                let scale = range ?? lowest ... highest
                Canvas { context, size in
                    context.stroke(path(in: size, scale: scale), with: .color(color), lineWidth: 1.5)
                }
                .frame(height: height)
                .background(Color.primary.opacity(0.03))
                .cornerRadius(3)
                .accessibilityElement()
                .accessibilityLabel(label)
                .accessibilityValue(spokenSummary(lowest: lowest, highest: highest))
            }
        }

        private func path(in size: CGSize, scale: ClosedRange<Double>) -> Path {
            // A flat range has no height to scale by; its samples sit on the bottom edge.
            let span = scale.upperBound - scale.lowerBound
            let effectiveSpan = span > 0 ? span : 1
            var path = Path()
            for (index, value) in data.enumerated() {
                let point = CGPoint(
                    x: size.width * CGFloat(index) / CGFloat(data.count - 1),
                    y: size.height * (1 - CGFloat((value - scale.lowerBound) / effectiveSpan))
                )
                if index == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
            return path
        }

        private func spokenSummary(lowest: Double, highest: Double) -> String {
            let style = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0 ... 1))
            let latest = data.last ?? lowest
            return "Latest \(latest.formatted(style)), lowest \(lowest.formatted(style)), highest \(highest.formatted(style))"
        }
    }
#endif
