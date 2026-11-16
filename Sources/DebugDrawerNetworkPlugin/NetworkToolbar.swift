#if DEBUG
    import SwiftUI

    /// The request count, the status filter and a button that clears every request.
    struct NetworkToolbar: View {
        let count: Int
        @Binding var filterStatus: NetworkStore.StatusFilter
        let clear: () -> Void
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            // At accessibility sizes the count, the filter and Clear don't fit one row, and squeezing
            // them breaks words, so the count takes its own line and the controls wrap below it.
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    countLabel
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) { controls }
                        VStack(alignment: .leading, spacing: 6) { controls }
                    }
                }
            } else {
                HStack(spacing: 6) {
                    countLabel
                    controls
                }
            }
        }

        private var countLabel: some View {
            Text("\(count)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        @ViewBuilder private var controls: some View {
            Picker("Status", selection: $filterStatus) {
                ForEach(NetworkStore.StatusFilter.allCases, id: \.self) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.mini)
            .accessibilityLabel("Status")
            .accessibilityElement(children: .contain)

            Button("Clear", action: clear)
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
    }
#endif
