import SwiftUI

/// A measure and how full it is, as Xcode's debug gauges show CPU and memory: the label in a
/// column of its own, a bar meter, then the value right-aligned in monospaced figures of one width,
/// its unit dimmed ("182.4 MB").
///
/// The bar fills in the accent color, or in an issue's color where that means something (frames
/// dropping, memory near its limit). VoiceOver reads the label, the value, and the fraction as a
/// percentage. At accessibility text sizes the label, the value and the bar each take a line.
///
/// ```swift
/// DebugDrawerGaugeRow("CPU", value: "38%", fraction: 0.38)
/// DebugDrawerGaugeRow("Frames", value: "52 fps", fraction: 52 / 60, severity: .warning)
/// ```
///
/// The type exists in every build so a plugin's body compiles unchanged in release, where it
/// draws nothing.
public struct DebugDrawerGaugeRow: View {
    let label: String
    let value: String
    let fraction: Double
    let severity: DebugDrawerIssueGlyph.Severity?

    /// - Parameters:
    ///   - label: What is measured ("Memory").
    ///   - value: The measure as shown, a figure and its unit ("182.4 MB").
    ///   - fraction: How full the bar is, from 0 to 1; values outside are clamped.
    ///   - severity: Fills the bar in that issue's color rather than the accent; `nil` for the
    ///     accent.
    public init(_ label: String, value: String, fraction: Double, severity: DebugDrawerIssueGlyph.Severity? = nil) {
        self.label = label
        self.value = value
        self.fraction = fraction
        self.severity = severity
    }

    public var body: some View {
        #if DEBUG
            DrawerGaugeRowLayout(row: self)
        #else
            EmptyView()
        #endif
    }
}

#if DEBUG
    extension DebugDrawerGaugeRow {
        /// How full the bar is, from 0 to 1.
        var clampedFraction: Double {
            min(max(fraction, 0), 1)
        }

        /// What VoiceOver reads after the label: the value, then how full the bar is ("182.4 MB,
        /// 62%").
        var spokenValue: String {
            "\(value), \(clampedFraction.formatted(.percent.precision(.fractionLength(0))))"
        }
    }

    /// The gauge row's face.
    struct DrawerGaugeRowLayout: View {
        let row: DebugDrawerGaugeRow
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        @ScaledMetric(relativeTo: .body) private var labelWidth = DrawerSpacing.gaugeLabelWidth
        @ScaledMetric(relativeTo: .body) private var barHeight = DrawerSpacing.gaugeHeight
        @ScaledMetric(relativeTo: .body) private var valueWidth = DrawerSpacing.gaugeValueWidth
        @ScaledMetric(relativeTo: .body) private var padding = DrawerSpacing.rowPadding
        @ScaledMetric(relativeTo: .body) private var gap = DrawerSpacing.itemGap

        var body: some View {
            let stacked = dynamicTypeSize.isAccessibilitySize
            let layout = stacked
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                : AnyLayout(HStackLayout(alignment: .center, spacing: gap))
            layout {
                Text(row.label)
                    .debugDrawerFont(.body)
                    .foregroundStyle(DrawerPalette.text)
                    // At least the column's width, so bars line up, and wider rather than broken
                    // inside a word ("Response"); the bar gives up the room.
                    .frame(minWidth: stacked ? nil : labelWidth, alignment: .leading)
                    .fixedSize(horizontal: !stacked, vertical: false)
                // At accessibility sizes the label, value and bar each take a line of their own.
                if stacked {
                    value
                    bar
                } else {
                    HStack(spacing: gap) {
                        bar
                        value
                            .frame(minWidth: valueWidth, alignment: .trailing)
                    }
                }
            }
            .padding(.vertical, padding)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(row.label)
            .accessibilityValue(row.spokenValue)
        }

        private var clamped: Double {
            row.clampedFraction
        }

        private var bar: some View {
            let shape = RoundedRectangle(cornerRadius: DrawerSpacing.gaugeRadius)
            return shape
                .fill(DrawerPalette.separator)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        shape
                            .fill(fill)
                            .frame(width: proxy.size.width * clamped)
                    }
                }
                .frame(height: barHeight)
                .frame(maxWidth: .infinity)
        }

        private var fill: Color {
            DrawerPalette.fill(for: row.severity)
        }

        private var value: some View {
            Group {
                if let measure = Measure(row.value) {
                    Text("\(Text(measure.figure))\(Text(measure.unit).foregroundStyle(DrawerPalette.tertiaryText))")
                } else {
                    Text(row.value)
                }
            }
            .debugDrawerFont(.value)
            .foregroundStyle(DrawerPalette.text)
            .fixedSize()
        }
    }
#endif
