import SwiftUI

/// A labelled value on one line: the label in a column of its own, the value in a monospaced font
/// beside it, selectable. At accessibility text sizes the label no longer fits its column, so it
/// sits above the value.
///
/// A sensitive value passes its redacted form, which shows until the eye button beside it reveals
/// the value (``RedactedText``).
///
/// The type exists in every build so a plugin's body compiles unchanged in release, where it
/// draws nothing.
public struct DebugDrawerKeyValueRow: View {
    let label: String
    let value: String
    let redacted: String
    @ScaledMetric private var labelWidth: CGFloat
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// - Parameters:
    ///   - label: What the value is ("Version").
    ///   - value: The value itself.
    ///   - redacted: What to show until revealed, such as ``DebugDrawerRedaction/mask``; `nil`
    ///     for a value that isn't sensitive.
    ///   - labelWidth: The width of the label column, in points at the default text size; it grows
    ///     with the text, and on tvOS, whose text is about twice as large, it doubles. Rows that
    ///     line up share one width.
    public init(_ label: String, value: String, redacted: String? = nil, labelWidth: CGFloat = 80) {
        self.label = label
        self.value = value
        self.redacted = redacted ?? value
        _labelWidth = ScaledMetric(wrappedValue: labelWidth * .debugDrawerTextScale, relativeTo: .caption)
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
    extension DebugDrawerKeyValueRow {
        private var isStacked: Bool {
            dynamicTypeSize.isAccessibilitySize
        }

        private var content: some View {
            let layout = isStacked
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
            return layout {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: isStacked ? nil : labelWidth, alignment: .leading)
                RedactedText(value, redacted: redacted)
                    .font(.system(.caption2, design: .monospaced))
                if !isStacked {
                    Spacer()
                }
            }
            // A row with a reveal button keeps it a control of its own; a plain one reads as one item.
            .accessibilityElement(children: value == redacted ? .combine : .contain)
        }
    }
#endif
