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
        @ScaledMetric private var iconWidth: CGFloat = 20 * .debugDrawerTextScale

        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            // At accessibility text sizes the icon's column leaves too little of the drawer's width
            // for a long word, which would break mid-word, so the text goes under the icon and takes
            // the row's whole width, as in a plugin's header (PluginHeaderLabel).
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                : AnyLayout(HStackLayout(spacing: 8))
            layout {
                Image(systemName: result.icon)
                    .frame(width: iconWidth)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(result.title)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    if let pluginTitle = result.pluginTitle {
                        Text(pluginTitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .background(isHighlighted ? Color.accentColor.opacity(0.15) : .clear)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isHighlighted ? .isSelected : [])
        }
    }
#endif
