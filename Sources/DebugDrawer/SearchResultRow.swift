#if DEBUG
    import SwiftUI

    /// One result in the drawer's search: the plugin's or action's icon and title, and for an
    /// action, the plugin it belongs to.
    struct SearchResultRow: View {
        let result: DrawerSearchResult
        /// The result Return runs.
        let isHighlighted: Bool
        /// The icon's column, which grows with the icon at larger text sizes so the title never
        /// slides under it.
        @ScaledMetric private var iconWidth: CGFloat = 20

        var body: some View {
            HStack(spacing: 8) {
                Image(systemName: result.icon)
                    .frame(width: iconWidth)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(result.title)
                        .font(.subheadline)
                    if let pluginTitle = result.pluginTitle {
                        Text(pluginTitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .background(isHighlighted ? Color.accentColor.opacity(0.15) : .clear)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isHighlighted ? .isSelected : [])
        }
    }
#endif
