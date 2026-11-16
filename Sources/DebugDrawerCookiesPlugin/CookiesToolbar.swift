#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The cookie count and the buttons that reload, delete and copy the cookies.
    struct CookiesToolbar: View {
        let count: Int
        let refresh: () -> Void
        let deleteAll: () -> Void
        let copy: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(count) cookies")
                    .debugDrawerFont(.value)
                    .debugDrawerForegroundStyle(.secondary)
                // The action row wraps its buttons, and stacks them at accessibility sizes.
                DebugDrawerActionRow {
                    Button("Refresh", action: refresh)
                    Button("Copy", action: copy)
                } trailing: {
                    Button("Delete All", role: .destructive, action: deleteAll)
                        .debugDrawerButtonStyle(.destructive)
                }
            }
        }
    }
#endif
