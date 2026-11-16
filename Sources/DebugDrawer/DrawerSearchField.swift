// watchOS has no filter field; its drawer is a navigation list (DrawerWatchList).
#if DEBUG && !os(watchOS)
    import SwiftUI

    /// The drawer's filter field: a funnel and the query on a light field with a hairline edge,
    /// as Xcode's navigators filter at their foot; on tvOS the system's own field. What it holds
    /// finds plugins and their actions.
    struct DrawerSearchField: View {
        @Binding var query: String

        var body: some View {
            TextField("Filter", text: $query)
            #if os(tvOS)
                .debugDrawerTextFieldStyle()
            #else
                .drawerTextFieldStyle(systemImage: "line.3.horizontal.decrease.circle")
            #endif
                .accessibilityLabel("Filter plugins and actions")
        }
    }
#endif
