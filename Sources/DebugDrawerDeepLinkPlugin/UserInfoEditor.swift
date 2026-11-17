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
                stacked
            } else {
                // The rows in columns while their ideal width fits: the menus at theirs and each
                // field at the least that still shows a few characters. Where it doesn't (an
                // iPad's drawer at the larger text sizes, whose menus grow with the text), the
                // rows stack, as at accessibility sizes, rather than run past the drawer's edges.
                ViewThatFits(in: .horizontal) {
                    columns
                    stacked
                }
            }
        }

        /// The rows in columns of key, type and value that line up from row to row.
        private var columns: some View {
            let kinds = UserInfoField.Kind.allCases.filter { kind in fields.contains { $0.kind == kind } }
            return VStack(alignment: .leading, spacing: 4) {
                ForEach($fields) { $field in
                    UserInfoFieldRow(field: $field, layout: .columns(kinds: kinds)) { remove(field) }
                }
            }
            .debugDrawerRowPadding()
        }

        /// Each row a stack of its own, a line per control.
        private var stacked: some View {
            // One view, so ViewThatFits takes the rows together rather than each as a choice.
            VStack(alignment: .leading, spacing: 0) {
                ForEach($fields) { $field in
                    UserInfoFieldRow(field: $field, layout: .stacked) { remove(field) }
                }
            }
        }

        private func remove(_ field: UserInfoField) {
            fields.removeAll { $0.id == field.id }
        }
    }

    /// One userInfo row: the key, a menu of its type, and the value, a field or a menu of true
    /// and false; a line of the editor's columns, or a stack of its own.
    struct UserInfoFieldRow: View {
        /// How the row lays out its controls.
        enum Layout {
            /// On one line, in the editor's columns, beside rows of `kinds`.
            case columns(kinds: [UserInfoField.Kind])
            /// A stack of its own, a line per control.
            case stacked
        }

        @Binding var field: UserInfoField
        let layout: Layout
        let onRemove: () -> Void
        /// A field's ideal width on a line: enough for a few characters. Fixed rather than the
        /// text's, so typing never moves the editor between columns and the stack.
        @ScaledMetric(relativeTo: .body) private var fieldIdealWidth: CGFloat = 44

        var body: some View {
            switch layout {
            case .columns:
                // A line of its own rather than a Grid's row: a grid shares the width its fixed
                // columns leave evenly between the key and the value, then widens the value
                // column to a Boolean's menu without taking the difference back from the key, so
                // a Boolean beside a String ran past an iPad's drawer. Each line has the same
                // slots instead (the type as wide as the widest menu of the kinds the editor
                // holds and, with a Boolean among them, the value at least as wide as the true
                // and false menu), so the lines share out the width alike and the columns line
                // up.
                HStack(spacing: 6) {
                    keyField
                    kindMenu
                    valueControl
                    removeButton
                }
            case .stacked:
                // A line holds one control, so the key and the remove button share the first and
                // the type and the value take one each below it.
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        keyField
                        removeButton
                    }
                    kindMenu
                    valueControl
                }
                .debugDrawerRowPadding()
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
                // A field gives up width before the menus do.
                .frame(minWidth: 0, idealWidth: fieldIdealWidth, maxWidth: .infinity)
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
            .frameOfWidestMenu(kindsBeside.map(\.rawValue))
        }

        /// The kinds of the rows this one lines up with: none when it's stacked.
        private var kindsBeside: [UserInfoField.Kind] {
            switch layout {
            case let .columns(kinds): kinds
            case .stacked: []
            }
        }

        /// The values of a Boolean's menu, when a row this one lines up with holds a Boolean.
        private var booleanTitlesBeside: [String] {
            kindsBeside.contains(.boolean) ? ["true", "false"] : []
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
                .frameOfWidestMenu(booleanTitlesBeside)
                .frame(maxWidth: .infinity, alignment: .leading)
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
                    .frame(minWidth: 0, idealWidth: fieldIdealWidth, maxWidth: .infinity)
                    .frameOfWidestMenu(booleanTitlesBeside)
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

    extension View {
        /// This view at least as wide as the widest of the row's small menus showing each of
        /// `titles`, so a column of them lines up from line to line whatever each line shows;
        /// as it is for no titles.
        fileprivate func frameOfWidestMenu(_ titles: [String]) -> some View {
            ZStack(alignment: .leading) {
                // Measured rather than given a width: a menu's width follows the platform, the
                // text size and the language.
                ForEach(titles, id: \.self) { title in
                    Picker(title, selection: .constant(title)) {
                        Text(title).tag(title)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .controlSize(.small)
                    .fixedSize()
                    .hidden()
                    .accessibilityLabel(title)
                    .accessibilityHidden(true)
                }
                self
            }
        }
    }
#endif
