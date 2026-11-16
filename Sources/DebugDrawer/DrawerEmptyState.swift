#if DEBUG
    import SwiftUI

    /// What the drawer shows when no plugin is registered.
    struct DrawerEmptyState: View {
        var body: some View {
            VStack(spacing: 8) {
                Image(systemName: "tray")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                Text("No plugins registered")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        }
    }
#endif
