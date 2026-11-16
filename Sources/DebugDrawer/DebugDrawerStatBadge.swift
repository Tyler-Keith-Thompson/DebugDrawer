import SwiftUI

/// A figure over its caption ("12" over "Total"), for a row of totals above a plugin's list or
/// graph.
///
/// The type exists in every build so a plugin's body compiles unchanged in release, where it
/// draws nothing.
public struct DebugDrawerStatBadge: View {
    let caption: String
    let value: String
    let color: Color

    /// - Parameters:
    ///   - caption: What the figure is ("Avg Time").
    ///   - value: The figure, formatted ("120ms").
    ///   - color: The figure's color, such as the color of the graph it summarises.
    public init(_ caption: String, value: String, color: Color = .primary) {
        self.caption = caption
        self.value = value
        self.color = color
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
    extension DebugDrawerStatBadge {
        private var content: some View {
            VStack(spacing: 1) {
                Text(value)
                    .font(.system(.caption2, design: .monospaced, weight: .bold))
                    .foregroundStyle(color)
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(caption)
            .accessibilityValue(value)
        }
    }
#endif
