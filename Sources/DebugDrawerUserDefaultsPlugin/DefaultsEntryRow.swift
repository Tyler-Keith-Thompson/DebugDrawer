#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// A key and its value's type; selected, it shows the value and the editor for it, whatever its
    /// type and however deep, a button to copy the value and one to delete the key, which asks
    /// first. A sensitive value is masked in the copy, and on screen until revealed. A key from a
    /// domain other than the persistent one names that domain and is read-only: its value, why it
    /// can't be edited, and Copy Value.
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
                        if let readOnlyReason = entry.domain.readOnlyReason {
                            valueText
                            Text(readOnlyReason)
                                .debugDrawerFont(.secondary)
                                .debugDrawerForegroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            // An array or a dictionary lists what it holds instead.
                            if entry.value.type != .array, entry.value.type != .dictionary {
                                valueText
                            }
                            PropertyListEditor(key: entry.key, value: entry.value, save: onSet)
                        }

                        DebugDrawerActionRow {
                            DebugDrawerCopyButton("Copy Value") { entry.copiedValue(redaction: redaction) }
                        } trailing: {
                            // Deleting from another domain would change nothing the suite reads.
                            if entry.domain == .persistent {
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
                    }
                    .padding(.bottom, 4)
                }
            }
            .onChange(of: isSelected) {
                if !isSelected { isConfirmingDelete = false }
            }
        }

        // The key in the drawer's code type with its value's type, and any domain but the
        // persistent one, after it in tertiary text; at
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

                Text(entry.typeAndDomain)
                    .debugDrawerFont(.secondary)
                    .debugDrawerForegroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .debugDrawerRowPadding()
            .contentShape(Rectangle())
        }

        private var valueText: some View {
            DebugDrawerCodeBlock {
                RedactedText(entry.value.copiedText, redacted: entry.copiedValue(redaction: redaction))
            }
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

    extension DefaultsEntry {
        /// The value's type, then the domain it comes from unless that is the persistent one
        /// ("Number · Registered").
        fileprivate var typeAndDomain: String {
            [value.type.title, domain.title].compactMap(\.self).joined(separator: " · ")
        }
    }
#endif
