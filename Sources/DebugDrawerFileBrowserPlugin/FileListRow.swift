#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// A row the browser opens: a symbol, a name and a size, with a line below it (a root's path)
    /// and a chevron, as rows that lead somewhere have in Xcode's navigators.
    struct FileListRow: View {
        let title: String
        let systemImage: String
        /// The size, or `nil` while a folder's total is counted.
        let size: String?
        /// A line below the name, such as a path.
        var detail: String?
        let hint: String
        let onOpen: () -> Void
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = 18

        var body: some View {
            Button(action: onOpen) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: systemImage)
                        .debugDrawerFont(.secondary)
                        .debugDrawerForegroundStyle(.secondary)
                        .frame(width: iconWidth)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        rowLayout {
                            Text(title)
                                .debugDrawerFont(.body)
                                .debugDrawerForegroundStyle(.primary)
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                                .truncationMode(.middle)
                                .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? nil : .infinity, alignment: .leading)
                            Text(size ?? "…")
                                .debugDrawerFont(.value)
                                .debugDrawerForegroundStyle(.tertiary)
                                .accessibilityLabel(size ?? "Size not counted yet")
                        }
                        if let detail {
                            Text(detail)
                                .debugDrawerFont(.code)
                                .debugDrawerForegroundStyle(.tertiary)
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                                .truncationMode(.middle)
                        }
                    }
                    Image(systemName: "chevron.right")
                        .debugDrawerFont(.secondary)
                        .debugDrawerForegroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .debugDrawerRowPadding()
                .contentShape(Rectangle())
            }
            .debugDrawerButtonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint(hint)
        }

        // At accessibility sizes the size goes below the name, so the name keeps the width.
        private var rowLayout: AnyLayout {
            dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
        }
    }

    extension Int64 {
        /// The byte count as Finder writes it: "12 kB", "3.2 MB", and "0 bytes" rather than
        /// "Zero kB", which reads as a word among figures.
        func byteCountText(_ locale: Locale) -> String {
            formatted(.byteCount(style: .file, spellsOutZero: false).locale(locale))
        }
    }
#endif
