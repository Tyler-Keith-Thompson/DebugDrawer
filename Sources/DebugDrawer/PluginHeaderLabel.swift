#if DEBUG
    import SwiftUI

    /// The face of a plugin's header row, as a group in Xcode's navigators: a filled disclosure
    /// triangle, pointing down while the plugin is open and right while closed, the title in bold,
    /// a pin when it's pinned, a crossed-out bell while its notices are silenced, and its count in a gray capsule at the trailing edge. A plugin with
    /// a header accessory shows no count: the accessory, beside this label, replaces it, so the
    /// header never draws two numbers. At accessibility text sizes the title wraps between words.
    struct PluginHeaderLabel: View {
        let plugin: AnyDebugDrawerPlugin
        let isExpanded: Bool
        let isPinned: Bool
        /// The plugin's badge count, if it has one.
        var badge: Int?
        /// Whether the plugin's badges and toasts are silenced.
        var isNoticesMuted = false
        @ScaledMetric(relativeTo: .body) private var minHeight = DrawerSpacing.sectionHeaderHeight
        @ScaledMetric(relativeTo: .body) private var triangle = DrawerSpacing.disclosure
        @ScaledMetric(relativeTo: .body) private var scaledIndent = DrawerSpacing.contentIndent
        @ScaledMetric(relativeTo: .body) private var scaledInset = DrawerSpacing.panelInset
        // The indent and margins grow with the text only a little: at accessibility sizes the
        // panel's width is better spent on the text.
        private var indent: CGFloat { min(scaledIndent, DrawerSpacing.contentIndent * 1.25) }
        private var inset: CGFloat { min(scaledInset, DrawerSpacing.panelInset * 1.25) }
        @ScaledMetric(relativeTo: .body) private var gap = DrawerSpacing.itemGap
        @ScaledMetric(relativeTo: .body) private var countPadding = DrawerSpacing.countPadding
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: gap) {
                Image(systemName: isExpanded ? "arrowtriangle.down.fill" : "arrowtriangle.right.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(DrawerPalette.secondaryText)
                    .frame(width: min(triangle, indent - gap), height: min(triangle, indent - gap))
                    // The triangle sits in the indent's width, so titles start where content does.
                    .frame(width: indent - gap, alignment: .leading)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - $0.height * 0.1 }
                    .accessibilityHidden(true)
                // At accessibility text sizes a word of the title can be wider than what the pin and
                // count leave it, so they go on a line of their own under the title.
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
                    : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: gap))
                layout {
                    Text(plugin.title)
                        .debugDrawerFont(.title)
                        .foregroundStyle(DrawerPalette.text)
                        .fixedSize(horizontal: false, vertical: true)
                        // The title takes the row's width left by the pin and count, which never wrap.
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .layoutPriority(1)
                    HStack(alignment: .firstTextBaseline, spacing: gap) {
                        marks
                    }
                }
            }
            .padding(.horizontal, inset)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
            .contentShape(Rectangle())
        }

        /// The pin, the silenced bell and the count.
        @ViewBuilder private var marks: some View {
            if isPinned {
                Image(systemName: "pin.fill")
                    .debugDrawerFont(.secondary)
                    .foregroundStyle(DrawerPalette.tertiaryText)
                    .fixedSize()
                    .accessibilityLabel("Pinned")
            }
            if isNoticesMuted {
                Image(systemName: "bell.slash")
                    .debugDrawerFont(.secondary)
                    .foregroundStyle(DrawerPalette.tertiaryText)
                    .fixedSize()
                    .accessibilityLabel("Notices silenced")
            }
            if let badge, !plugin.hasHeaderAccessory {
                Text(badge, format: .number)
                    .debugDrawerFont(.secondary)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .fixedSize()
                    .foregroundStyle(DrawerPalette.secondaryText)
                    .padding(.horizontal, countPadding)
                    .background(Capsule().fill(DrawerPalette.separator))
                    .accessibilityLabel("\(badge) new")
            }
        }
    }
#endif
