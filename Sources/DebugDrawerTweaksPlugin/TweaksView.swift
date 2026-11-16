#if DEBUG
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
            VStack(alignment: .leading, spacing: 8) {
                if sections.allSatisfy(\.rows.isEmpty) {
                    Text("No tweaks declared")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(section.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(section.rows) { row in
                                TweakRow(
                                    row: row,
                                    onChange: { onChange(row.id, $0) },
                                    onReset: { onReset(row.id) }
                                )
                            }
                        }
                        Divider()
                    }

                    Button("Reset All", action: onResetAll)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!sections.contains { $0.rows.contains(where: \.isModified) })
                        .accessibilityHint("Resets every tweak to its default")
                }
            }
        }
    }
#endif
