#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// An activity's userInfo as rows of key, type and value, as Xcode's property list editor
    /// lays them out, each with a button that removes it.
    struct UserInfoEditor: View {
        @Binding var fields: [UserInfoField]
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            if dynamicTypeSize.isAccessibilitySize {
                ForEach($fields) { $field in
                    UserInfoFieldRow(field: $field) { remove(field) }
                }
            } else {
                // A grid, so the key, type and value line up in columns from row to row. The
                // menus keep their ideal width; the key and a typed value share the rest, so a row
                // never runs wider than the drawer.
                Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 4) {
                    ForEach($fields) { $field in
                        UserInfoFieldRow(field: $field) { remove(field) }
                    }
                }
                .debugDrawerRowPadding()
            }
        }

        private func remove(_ field: UserInfoField) {
            fields.removeAll { $0.id == field.id }
        }
    }

    /// One userInfo row: the key, a menu of its type, and the value, a field or a menu of true
    /// and false; a row of the editor's grid, or at accessibility text sizes, a stack of its own.
    struct UserInfoFieldRow: View {
        @Binding var field: UserInfoField
        let onRemove: () -> Void
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            // At accessibility text sizes a line holds one control, so the key and the remove
            // button share the first and the type and the value take one each below it.
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        keyField
                        removeButton
                    }
                    kindMenu
                    valueControl
                }
                .debugDrawerRowPadding()
            } else {
                GridRow {
                    keyField
                    kindMenu
                    valueControl
                    removeButton
                }
            }
        }

        private var keyField: some View {
            TextField("Key", text: $field.key)
                .debugDrawerFont(.code)
                .debugDrawerTextFieldStyle()
                .autocorrectionDisabled()
                .accessibilityLabel("Key")
                #if os(iOS)
                    .autocapitalization(.none)
                #endif
                // A field gives up width before the menus do, down to none, so a row of a Boolean
                // fits however narrow the drawer is.
                .frame(minWidth: 0, maxWidth: .infinity)
        }

        private var kindMenu: some View {
            Picker("Type", selection: $field.kind) {
                ForEach(UserInfoField.Kind.allCases, id: \.self) { kind in
                    Text(kind.rawValue).tag(kind)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
            .accessibilityLabel("Type of \(field.key)")
        }

        @ViewBuilder private var valueControl: some View {
            switch field.kind {
            case .boolean:
                // A menu of true and false, as Xcode's property list editor offers YES and NO: it
                // reads the same in an inactive window, where a switch loses its color.
                Picker("Value of \(field.key)", selection: $field.isOn) {
                    Text("true").tag(true)
                    Text("false").tag(false)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
                .accessibilityLabel("Value of \(field.key)")
            case .string, .number:
                TextField(field.kind == .number ? "0" : "Value", text: $field.text)
                    .debugDrawerFont(.code)
                    .debugDrawerTextFieldStyle()
                    .autocorrectionDisabled()
                    .accessibilityLabel("Value of \(field.key)")
                    #if os(iOS)
                        .autocapitalization(.none)
                        .keyboardType(field.kind == .number ? .numbersAndPunctuation : .default)
                    #endif
                    .frame(minWidth: 0, maxWidth: .infinity)
            }
        }

        private var removeButton: some View {
            Button(action: onRemove) {
                Label("Remove", systemImage: "minus.circle")
                    .labelStyle(.iconOnly)
            }
            .debugDrawerButtonStyle(.borderless)
            .accessibilityLabel("Remove \(field.key)")
            .help("Remove the key")
        }
    }
#endif
