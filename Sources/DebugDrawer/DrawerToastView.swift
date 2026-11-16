#if DEBUG
    import SwiftUI

    /// A plugin's toast: its icon, title and latest message, how many posts it stands for, a tap
    /// target that opens the drawer at the plugin, and a dismiss button.
    struct DrawerToastView: View {
        let toast: DebugDrawerToast
        /// The plugin that raised it, if it's still registered.
        let plugin: AnyDebugDrawerPlugin?
        let open: () -> Void
        let dismiss: () -> Void

        var body: some View {
            HStack(alignment: .top, spacing: 8) {
                Button(action: open) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: plugin?.icon ?? "ladybug")
                            .foregroundStyle(.orange)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(plugin?.title ?? toast.pluginID)
                                .font(.caption.weight(.semibold))
                            Text(toast.message)
                                .font(.caption)
                                .lineLimit(3)
                        }
                        Spacer(minLength: 0)
                        if toast.count > 1 {
                            Text(toast.count, format: .number)
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("\(toast.count) notices")
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the debug drawer at this plugin")

                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
            .padding(10)
            .frame(maxWidth: 320, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
            .padding(12)
        }
    }
#endif
