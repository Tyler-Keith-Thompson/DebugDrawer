#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// A key and its value's type; selected, it shows the value, controls to change it (Bool,
    /// String and Number values), a button to copy the value and one to delete the key, which
    /// asks first. A sensitive value is masked in the copy, and on screen until revealed.
    struct DefaultsEntryRow: View {
        let entry: DefaultsEntry
        let redaction: DebugDrawerRedaction
        let isSelected: Bool
        let onSelect: () -> Void
        let onSet: (Any) -> Void
        let onDelete: () -> Void
        @State private var editValue: String
        @State private var isConfirmingDelete = false
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        init(
            entry: DefaultsEntry,
            redaction: DebugDrawerRedaction,
            isSelected: Bool,
            onSelect: @escaping () -> Void,
            onSet: @escaping (Any) -> Void,
            onDelete: @escaping () -> Void
        ) {
            self.entry = entry
            self.redaction = redaction
            self.isSelected = isSelected
            self.onSelect = onSelect
            self.onSet = onSet
            self.onDelete = onDelete
            _editValue = State(initialValue: entry.value)
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Button(action: onSelect) {
                    summary
                }
                .debugDrawerButtonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])

                if isSelected {
                    VStack(alignment: .leading, spacing: 4) {
                        DebugDrawerCodeBlock {
                            RedactedText(entry.value, redacted: entry.copiedValue(redaction: redaction))
                        }

                        editControls

                        DebugDrawerActionRow {
                            DebugDrawerCopyButton("Copy Value") { entry.copiedValue(redaction: redaction) }
                        } trailing: {
                            if isConfirmingDelete {
                                deleteConfirmation
                            } else {
                                Button("Delete", role: .destructive) { isConfirmingDelete = true }
                                    .debugDrawerButtonStyle(.destructive)
                            }
                        }
                    }
                    .padding(.bottom, 4)
                }
            }
            .onChange(of: isSelected) {
                if isSelected { editValue = entry.value }
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

                Text(entry.type)
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
                Button("Delete", role: .destructive) {
                    isConfirmingDelete = false
                    onDelete()
                }
                .debugDrawerButtonStyle(.destructive)
                .accessibilityLabel("Delete \(entry.key)")
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Delete \(entry.key)?")
        }

        @ViewBuilder
        private var editControls: some View {
            switch entry.type {
            case "Bool":
                HStack {
                    Text("Value")
                        .debugDrawerFont(.label)
                        .debugDrawerForegroundStyle(.secondary)
                    Picker("Value", selection: Binding(
                        get: { (entry.rawValue as? NSNumber)?.boolValue ?? false },
                        set: { onSet($0) }
                    )) {
                        Text("true").tag(true)
                        Text("false").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(width: 120)
                    .accessibilityLabel("Value of \(entry.key)")
                    .accessibilityElement(children: .contain)
                }

            case "String":
                HStack {
                    valueField
                    Button("Set") { onSet(editValue) }
                        .debugDrawerButtonStyle(.secondary)
                        .accessibilityLabel("Set \(entry.key)")
                }

            case "Number":
                HStack {
                    valueField
                    Button("Set") {
                        if let number = Double(editValue) {
                            onSet(number)
                        } else if let integer = Int(editValue) {
                            onSet(integer)
                        }
                    }
                    .debugDrawerButtonStyle(.secondary)
                    .accessibilityLabel("Set \(entry.key)")
                }

            default:
                Text("Editing not supported for \(entry.type)")
                    .debugDrawerFont(.secondary)
                    .debugDrawerForegroundStyle(.tertiary)
            }
        }

        private var valueField: some View {
            TextField("New value", text: $editValue)
                .debugDrawerTextFieldStyle()
                .accessibilityLabel("New value for \(entry.key)")
        }
    }
#endif
