// watchOS shows a plugin alone in its navigation list instead (DrawerWatchPluginView).
#if DEBUG && !os(watchOS)
    import SwiftUI

    /// One plugin alone at the panel's full height, as Xcode shows an item a navigator focuses
    /// on: a heading row with the plugin's icon, title and header accessory, a hairline, then its
    /// body, scrolled on its own.
    struct DrawerPluginDetail: View {
        let plugin: AnyDebugDrawerPlugin
        @ScaledMetric(relativeTo: .body) private var scaledInset = DrawerSpacing.panelInset
        @ScaledMetric(relativeTo: .body) private var minHeight = DrawerSpacing.sectionHeaderHeight
        @ScaledMetric(relativeTo: .body) private var gap = DrawerSpacing.itemGap
        @ScaledMetric(relativeTo: .body) private var padding = DrawerSpacing.rowPadding
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        // The margins grow with the text only a little: at accessibility sizes the panel's width
        // is better spent on the text.
        private var inset: CGFloat { min(scaledInset, DrawerSpacing.panelInset * 1.25) }

        var body: some View {
            VStack(spacing: 0) {
                heading
                DrawerRule()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        plugin.body
                    }
                    .debugDrawerFont(.body)
                    .foregroundStyle(DrawerPalette.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, inset)
                    .padding(.vertical, padding)
                }
            }
        }

        /// The plugin's icon and title, and its header accessory beside them, or under them at
        /// accessibility sizes and when the two don't fit on one line.
        @ViewBuilder private var heading: some View {
            if let accessory = plugin.headerAccessory {
                if dynamicTypeSize.isAccessibilitySize {
                    headingRow(accessory, below: true)
                } else {
                    ViewThatFits(in: .horizontal) {
                        headingRow(accessory, below: false)
                        headingRow(accessory, below: true)
                    }
                }
            } else {
                title
            }
        }

        private var title: some View {
            HStack(spacing: gap) {
                Image(systemName: plugin.icon)
                    .foregroundStyle(DrawerPalette.secondaryText)
                    .accessibilityHidden(true)
                Text(plugin.title)
                    .debugDrawerFont(.title)
                    .foregroundStyle(DrawerPalette.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
            }
            .padding(.horizontal, inset)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
        }

        private func headingRow(_ accessory: AnyView, below: Bool) -> some View {
            let layout = below
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
                : AnyLayout(HStackLayout(spacing: 0))
            return layout {
                title
                accessory
                    .debugDrawerFont(.code)
                    .foregroundStyle(DrawerPalette.tertiaryText)
                    .debugDrawerButtonStyle(.borderless)
                    .fixedSize(horizontal: !below, vertical: true)
                    .padding(.leading, below ? inset : 0)
                    .padding(.trailing, inset)
                    .padding(.bottom, below ? padding : 0)
            }
        }
    }
#endif
