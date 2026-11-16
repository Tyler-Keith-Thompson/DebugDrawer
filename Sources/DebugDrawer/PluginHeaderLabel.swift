#if DEBUG
    import SwiftUI

    /// The face of a plugin's section header: its icon and title, a pin when it's pinned, and a
    /// chevron that turns down while the section is expanded.
    struct PluginHeaderLabel: View {
        let plugin: AnyDebugDrawerPlugin
        let isExpanded: Bool
        let isPinned: Bool

        var body: some View {
            HStack(spacing: 8) {
                Image(systemName: plugin.icon)
                    .frame(width: 20)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(plugin.title)
                    .font(.subheadline.weight(.medium))
                if isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .accessibilityLabel("Pinned")
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
    }
#endif
