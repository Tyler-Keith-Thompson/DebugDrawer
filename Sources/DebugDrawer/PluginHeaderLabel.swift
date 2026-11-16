#if DEBUG
    import SwiftUI

    /// The face of a plugin's section header: its icon and title, a pin when it's pinned, and a
    /// chevron that turns down while the section is expanded. At accessibility text sizes the
    /// title takes a line of its own below the rest, so it wraps between words rather than within
    /// them.
    struct PluginHeaderLabel: View {
        let plugin: AnyDebugDrawerPlugin
        let isExpanded: Bool
        let isPinned: Bool
        /// The plugin's badge count, if it has one.
        var badge: Int?
        /// The icon's column, which grows with the icon at larger text sizes so the title never
        /// slides under it.
        @ScaledMetric private var iconWidth: CGFloat = 20
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            icon
                            pin
                            Spacer()
                            trailing
                        }
                        // Without this, a title just wider than the line is cut short with an
                        // ellipsis rather than wrapped.
                        title
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    HStack(spacing: 8) {
                        icon
                        title
                        pin
                        Spacer()
                        trailing
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }

        private var icon: some View {
            Image(systemName: plugin.icon)
                .frame(width: iconWidth)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }

        private var title: some View {
            Text(plugin.title)
                .font(.subheadline.weight(.medium))
        }

        @ViewBuilder
        private var pin: some View {
            if isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("Pinned")
            }
        }

        /// The badge, if any, and the chevron.
        @ViewBuilder
        private var trailing: some View {
            if let badge {
                Text(badge, format: .number)
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(.red))
                    .accessibilityLabel("\(badge) new")
            }
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .accessibilityHidden(true)
        }
    }
#endif
