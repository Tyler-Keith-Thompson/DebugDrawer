#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The status filter, and a button that clears every request at the trailing edge. The
    /// request count is the header's accessory, so the toolbar doesn't repeat it.
    struct NetworkToolbar: View {
        @Binding var filterStatus: NetworkStore.StatusFilter
        let clear: () -> Void

        var body: some View {
            // The filter has a line of its own: its five segments at their ideal width are wider
            // than the drawer on iPad, and squeezed beside Clear they would truncate.
            VStack(alignment: .leading, spacing: 0) {
                Picker("Status", selection: $filterStatus) {
                    ForEach(NetworkStore.StatusFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("Status")
                .accessibilityElement(children: .contain)
                .padding(.top, 8)
                DebugDrawerActionRow {
                    EmptyView()
                } trailing: {
                    Button("Clear", role: .destructive, action: clear)
                        .debugDrawerButtonStyle(.destructive)
                        .accessibilityLabel("Clear requests")
                }
            }
        }
    }
#endif
