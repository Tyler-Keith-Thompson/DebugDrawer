#if DEBUG
    import SwiftUI

    /// What the drawer shows when no plugin is registered.
    struct DrawerEmptyState: View {
        var body: some View {
            DebugDrawerEmptyState("No plugins registered", systemImage: "tray")
        }
    }
#endif
