#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The flags, filtered by a search and an overridden-only switch, then buttons that read the
    /// provider again and clear every override.
    struct FeatureFlagsView: View {
        let rows: [FeatureFlagRowState]
        /// How many overrides are stored, including any for a flag the provider no longer lists.
        let overrideCount: Int
        @Binding var query: String
        @Binding var isOverriddenOnly: Bool
        /// Overrides a flag, by its key.
        let onOverride: (String, FeatureFlagValue) -> Void
        /// Clears a flag's override, by its key.
        let onClear: (String) -> Void
        let onClearAll: () -> Void
        let onRefresh: () -> Void
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        /// The tallest the list grows before it scrolls, larger as text grows.
        @ScaledMetric(relativeTo: .caption) private var listHeight: CGFloat = 250

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                let list = FeatureFlagList(rows, query: query, overriddenOnly: isOverriddenOnly)
                if list == .noFlags {
                    Text("The provider lists no flags")
                        .debugDrawerFont(.secondary)
                        .debugDrawerForegroundStyle(.secondary)
                } else {
                    filters
                    // The field stays while nothing matches, so the search can be changed.
                    DebugDrawerSearchableList("Filter...", text: $query, accessibilityLabel: "Filter flags by key or title", maxHeight: listHeight) {
                        if case let .flags(matching) = list {
                            ForEach(matching) { row in
                                FeatureFlagRow(
                                    row: row,
                                    onOverride: { onOverride(row.id, $0) },
                                    onClear: { onClear(row.id) }
                                )
                            }
                        } else {
                            Text(isOverriddenOnly && query.isEmpty ? "No flag is overridden" : "No flag matches")
                                .debugDrawerFont(.secondary)
                                .debugDrawerForegroundStyle(.secondary)
                                .debugDrawerRowPadding()
                        }
                    }
                }
                buttons
            }
        }

        /// The overridden-only switch and the count of overrides.
        private var filters: some View {
            stacked {
                Toggle("Overridden only", isOn: $isOverriddenOnly)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .debugDrawerFont(.body)
                if !dynamicTypeSize.isAccessibilitySize {
                    Spacer()
                }
                Text(overrideCount == 1 ? "1 override" : "\(overrideCount) overrides")
                    .debugDrawerFont(.value)
                    .debugDrawerForegroundStyle(.secondary)
            }
        }

        private var buttons: some View {
            DebugDrawerActionRow {
                Button("Refresh", action: onRefresh)
                    .accessibilityHint("Reads the flags and their live values again")
            } trailing: {
                Button("Reset All", role: .destructive, action: onClearAll)
                    .debugDrawerButtonStyle(.destructive)
                    .disabled(overrideCount == 0)
                    .accessibilityHint("Clears every override, so each flag reads its live value")
            }
        }

        /// Side by side, or one above the other at accessibility text sizes, where side by side
        /// leaves each too little width.
        private func stacked(@ViewBuilder _ content: () -> some View) -> some View {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                : AnyLayout(HStackLayout())
            return layout(content)
        }
    }
#endif
