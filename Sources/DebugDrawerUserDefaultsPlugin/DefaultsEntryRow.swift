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
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])

                if isSelected {
                    VStack(alignment: .leading, spacing: 4) {
                        RedactedText(entry.value, redacted: entry.copiedValue(redaction: redaction))
                            .font(.system(.caption2, design: .monospaced))
                            .padding(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.primary.opacity(0.05))
                            .cornerRadius(3)

                        editControls

                        // At accessibility text sizes the two buttons don't fit one line, so
                        // they stack.
                        let actionsLayout = stackingLayout()
                        actionsLayout {
                            Button("Copy Value") {
                                debugDrawerCopyToClipboard(entry.copiedValue(redaction: redaction))
                            }
                            .controlSize(.small)
                            .buttonStyle(.bordered)

                            if !dynamicTypeSize.isAccessibilitySize {
                                Spacer()
                            }
                            if isConfirmingDelete {
                                deleteConfirmation
                            } else {
                                Button("Delete") { isConfirmingDelete = true }
                                    .controlSize(.small)
                                    .buttonStyle(.bordered)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 4)
                }

                Divider().padding(.leading, 6)
            }
            .onChange(of: isSelected) {
                if isSelected { editValue = entry.value }
            }
        }

        /// Side by side, or stacked at accessibility text sizes, where side by side doesn't fit.
        private func stackingLayout(spacing: CGFloat? = nil) -> AnyLayout {
            dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                : AnyLayout(HStackLayout(spacing: spacing))
        }

        // At accessibility text sizes the type badge leaves the key too little width, so it
        // sits below the key.
        private var summary: some View {
            let layout = stackingLayout(spacing: 4)
            return layout {
                Text(entry.key)
                    .font(.system(.caption2, design: .monospaced))
                    .lineLimit(3)
                    .truncationMode(.middle)

                if !dynamicTypeSize.isAccessibilitySize {
                    Spacer()
                }

                Text(entry.type)
                    .font(.system(.caption2, design: .monospaced, weight: .medium))
                    .padding(.horizontal, 3)
                    .background(typeColor(entry.type).opacity(0.15))
                    .cornerRadius(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }

        private var deleteConfirmation: some View {
            HStack {
                Text("Sure?")
                    .font(.caption)
                    .foregroundStyle(.red)
                Button("Yes") {
                    isConfirmingDelete = false
                    onDelete()
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .tint(.red)
                Button("Cancel") { isConfirmingDelete = false }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Delete \(entry.key)?")
        }

        @ViewBuilder
        private var editControls: some View {
            switch entry.type {
            case "Bool":
                HStack {
                    Text("Value:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                        .controlSize(.small)
                        .buttonStyle(.bordered)
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
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Set \(entry.key)")
                }

            default:
                Text("Editing not supported for \(entry.type)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }

        private var valueField: some View {
            TextField("New value", text: $editValue)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .accessibilityLabel("New value for \(entry.key)")
        }

        private func typeColor(_ type: String) -> Color {
            switch type {
            case "String": .blue
            case "Bool": .green
            case "Number": .orange
            case "Date": .purple
            case "Data": .red
            case "Array", "Dict": .cyan
            default: .secondary
            }
        }
    }
#endif
