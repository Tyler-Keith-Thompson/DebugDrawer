#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The tweaks in their sections, then a button that resets every tweak to its default.
    struct TweaksView: View {
        let sections: [TweakSectionState]
        /// Stores a tweak's new value, by its key.
        let onChange: (String, TweakStoredValue) -> Void
        /// Resets a tweak to its default, by its key.
        let onReset: (String) -> Void
        let onResetAll: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                if sections.allSatisfy(\.rows.isEmpty) {
                    Text("No tweaks declared")
                        .debugDrawerFont(.secondary)
                        .debugDrawerForegroundStyle(.secondary)
                } else {
                    ForEach(sections) { section in
                        DebugDrawerSection(section.title) {
                            ForEach(section.rows) { row in
                                TweakRow(
                                    row: row,
                                    onChange: { onChange(row.id, $0) },
                                    onReset: { onReset(row.id) }
                                )
                            }
                        }
                    }

                    DebugDrawerActionRow {
                        EmptyView()
                    } trailing: {
                        Button("Reset All", role: .destructive, action: onResetAll)
                            .debugDrawerButtonStyle(.destructive)
                            .disabled(!sections.contains { $0.rows.contains(where: \.isModified) })
                            .accessibilityHint("Resets every tweak to its default")
                    }
                }
            }
        }
    }
#endif
