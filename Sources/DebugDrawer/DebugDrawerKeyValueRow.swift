import SwiftUI

/// An inspector form row, as in Xcode's inspectors: the label right-aligned in a column of its
/// own, the value left-aligned beside it, selectable. A value that is a figure, a version, a path
/// or a key is set in the drawer's monospaced value type; one in words ("Not Supported", "AC
/// Power") in the system font (``DebugDrawerValueStyle``, set with `debugDrawerValueStyle(_:)`).
/// Words wrap; a value of one token, such as an identifier, keeps to one line cut in the middle,
/// so both its ends show. A value that is a figure and its unit ("63.5 MB", "11s") shows the unit dimmed,
/// so the figures stand out. At accessibility text sizes the label no longer fits its column, so
/// it sits above the value, and an identifier wraps.
///
/// A sensitive value passes its redacted form, which shows until the eye button beside it reveals
/// the value (``RedactedText``). Rows pad themselves, so they stack with no spacing.
///
/// The type exists in every build so a plugin's body compiles unchanged in release, where it
/// draws nothing.
public struct DebugDrawerKeyValueRow: View {
    let label: String
    let value: String
    let redacted: String
    @ScaledMetric private var labelWidth: CGFloat
    @ScaledMetric(relativeTo: .body) private var padding = DrawerSpacing.rowPadding
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #if DEBUG
        // Chosen over an init parameter: one modifier covers a group of rows (every header of a
        // request), and the common case, figures beside words, needs no argument at all.
        @Environment(\.debugDrawerValueStyle) private var valueStyle
    #endif

    /// - Parameters:
    ///   - label: What the value is ("Version").
    ///   - value: The value itself.
    ///   - redacted: What to show until revealed, such as ``DebugDrawerRedaction/mask``; `nil`
    ///     for a value that isn't sensitive.
    ///   - labelWidth: The width of the key column, in points at the default text size (96 on
    ///     iOS, 82 on the Mac unless given); it grows with the text, and on tvOS, whose text is
    ///     about twice as large, it doubles. Rows that line up share one width.
    public init(_ label: String, value: String, redacted: String? = nil, labelWidth: CGFloat? = nil) {
        self.label = label
        self.value = value
        self.redacted = redacted ?? value
        _labelWidth = ScaledMetric(wrappedValue: (labelWidth ?? DrawerSpacing.formLabelWidth) * .debugDrawerTextScale, relativeTo: .body)
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
        /// The label sits above the value at accessibility sizes, and always on a watch, whose
        /// screen leaves a value beside a label column too little room.
        private var isStacked: Bool {
            #if os(watchOS)
                true
            #else
                dynamicTypeSize.isAccessibilitySize
            #endif
        }

        private var content: some View {
            let layout = isStacked
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
            return layout {
                Text(label)
                    .debugDrawerFont(.label)
                    .foregroundStyle(DrawerPalette.secondaryText)
                    .multilineTextAlignment(isStacked ? .leading : .trailing)
                    .frame(width: isStacked ? nil : labelWidth, alignment: isStacked ? .leading : .trailing)
                valueText
                    // A redacted value shows its mask until revealed; the mask is code.
                    .font(value != redacted || valueStyle.isCode(value) ? DebugDrawerTextStyle.value.font : DebugDrawerTextStyle.wordValue)
                    .foregroundStyle(DrawerPalette.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, padding)
            // A row with a reveal button keeps it a control of its own; a plain one reads as one item.
            .accessibilityElement(children: value == redacted ? .combine : .contain)
        }

        @ViewBuilder private var valueText: some View {
            if value != redacted {
                RedactedText(value, redacted: redacted)
            } else if let measure = Measure(value) {
                Text("\(Text(measure.figure))\(Text(measure.unit).foregroundStyle(DrawerPalette.tertiaryText))")
                    .debugDrawerTextSelection()
            } else if value.isEmpty || value.contains(where: \.isWhitespace) {
                Text(value)
                    .debugDrawerTextSelection()
            } else {
                // A single token, such as an identifier, keeps both ends on one line rather than
                // breaking (and hyphenating) inside it; it stays selectable whole. At accessibility
                // sizes a line holds too little of it, so it wraps rather than lose its middle.
                Text(value)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .truncationMode(.middle)
                    .debugDrawerTextSelection()
                    .help(value)
            }
        }
    }
#endif
