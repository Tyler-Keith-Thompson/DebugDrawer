#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// A key and its value's type; selected, it shows the value and the editor for it, whatever its
    /// type and however deep, a button to copy the value and one to delete the key, which asks
    /// first. A sensitive value is masked in the copy, and on screen until revealed.
    struct DefaultsEntryRow: View {
        let entry: DefaultsEntry
        let redaction: DebugDrawerRedaction
        let isSelected: Bool
        let onSelect: () -> Void
        /// Saves the key's whole value.
        let onSet: (PropertyListValue) -> Void
        let onDelete: () -> Void
        @State private var isConfirmingDelete = false
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Button(action: onSelect) {
                    summary
                }
                .debugDrawerButtonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])

                if isSelected {
                    VStack(alignment: .leading, spacing: 4) {
                        // An array or a dictionary lists what it holds instead.
                        if entry.value.type != .array, entry.value.type != .dictionary {
                            DebugDrawerCodeBlock {
                                RedactedText(entry.value.copiedText, redacted: entry.copiedValue(redaction: redaction))
                            }
                        }

                        PropertyListEditor(key: entry.key, value: entry.value, save: onSet)

                        DebugDrawerActionRow {
                            DebugDrawerCopyButton("Copy Value") { entry.copiedValue(redaction: redaction) }
                        } trailing: {
                            if isConfirmingDelete {
                                deleteConfirmation
                            } else {
                                // "Key", so it reads apart from a nested value's Delete Item.
                                Button("Delete Key", role: .destructive) { isConfirmingDelete = true }
                                    .debugDrawerButtonStyle(.destructive)
                                    .accessibilityLabel("Delete Key \(entry.key)")
                            }
                        }
                    }
                    .padding(.bottom, 4)
                }
            }
            .onChange(of: isSelected) {
                if !isSelected { isConfirmingDelete = false }
            }
        }

        // The key in the drawer's code type with its value's type after it in tertiary text; at
        // accessibility text sizes the type leaves the key too little width, so it sits below.
        // The key keeps to one line cut in the middle, so both its ends show: wrapped, a camel-case
        // key breaks (and hyphenates) inside a word, and SwiftUI's text can't turn hyphenation
        // off. Selected, it shows whole; VoiceOver always reads it whole.
        private var summary: some View {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 4))
            return layout {
                Text(entry.key)
                    .debugDrawerFont(.code)
                    .debugDrawerForegroundStyle(.primary)
                    .lineLimit(isSelected ? nil : 1)
                    .truncationMode(.middle)
                    .help(entry.key)

                if !dynamicTypeSize.isAccessibilitySize {
                    Spacer()
                }

                Text(entry.value.type.title)
                    .debugDrawerFont(.secondary)
                    .debugDrawerForegroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .debugDrawerRowPadding()
            .contentShape(Rectangle())
        }

        private var deleteConfirmation: some View {
            HStack {
                Text("Sure?")
                    .debugDrawerFont(.body)
                    .debugDrawerForegroundStyle(.error)
                Button("Cancel") { isConfirmingDelete = false }
                    .debugDrawerButtonStyle(.secondary)
                Button("Delete Key", role: .destructive) {
                    isConfirmingDelete = false
                    onDelete()
                }
                .debugDrawerButtonStyle(.destructive)
                .accessibilityLabel("Delete Key \(entry.key)")
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Delete Key \(entry.key)?")
        }
    }
#endif
