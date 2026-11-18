#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// A control for a value that holds no others: true or false, saved as it is picked; a date
    /// picker; or a field for a string, a number or data, which shows data in hex or Base64 as
    /// toggled. Text that isn't a value of the type says why below the field, and Save waits until
    /// it is. A value inside an array or a dictionary also offers Delete Item, across from Save.
    struct PropertyListScalarEditor: View {
        let value: PropertyListValue
        /// Where the value is: the key, then each step inside it ("settings › theme › accent").
        let title: String
        /// The field's name: "New value" for a key's own value, or `title` for one inside it, so
        /// the path stays in sight above the field while the keyboard scrolls the list.
        let fieldTitle: String
        /// Removes the value from what holds it; `nil` for a key's own value.
        let deleteItem: (() -> Void)?
        let save: (PropertyListValue) -> Void
        @State private var text: String
        @State private var date: Date
        @State private var encoding = DataTextEncoding.hex
        let inspection = Inspection<Self>()

        /// - Parameters:
        ///   - value: The value to start from: a string, number, Boolean, date or data.
        ///   - title: Where the value is, for the field's name inside a container and VoiceOver.
        ///   - deleteItem: Removes a value inside an array or dictionary; `nil` for a key's own.
        ///   - save: Saves the edited value.
        init(
            value: PropertyListValue,
            title: String,
            deleteItem: (() -> Void)? = nil,
            save: @escaping (PropertyListValue) -> Void
        ) {
            self.value = value
            self.title = title
            self.fieldTitle = deleteItem == nil ? "New value" : title
            self.deleteItem = deleteItem
            self.save = save
            _text = State(initialValue: value.fieldText)
            if case let .date(date) = value {
                _date = State(initialValue: date)
            } else {
                _date = State(initialValue: .distantPast)
            }
        }

        var body: some View {
            Group {
                switch value {
                case let .bool(isOn):
                    boolean(isOn)
                case .date:
                    dateEditor
                case .string, .number, .data:
                    textEditor
                case .array, .dictionary:
                    EmptyView()
                }
            }
            .onReceive(inspection.notice) { inspection.visit(self, $0) }
        }

        /// What the value is, for VoiceOver ("Value of launchCount").
        private var name: String { "Value of \(title)" }

        private func boolean(_ isOn: Bool) -> some View {
            DebugDrawerActionRow {
                Picker("Value", selection: Binding(get: { isOn }, set: { save(.bool($0)) })) {
                    Text("true").tag(true)
                    Text("false").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel(name)
                .accessibilityElement(children: .contain)
            } trailing: {
                deleteItemButton
            }
        }

        private var dateEditor: some View {
            DebugDrawerActionRow {
                DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .accessibilityLabel(name)
                Button("Save") { save(.date(date)) }
                    .debugDrawerButtonStyle(.primary)
                    .accessibilityLabel("Save \(name)")
            } trailing: {
                deleteItemButton
            }
        }

        @ViewBuilder
        private var deleteItemButton: some View {
            if let deleteItem {
                Button("Delete Item", role: .destructive, action: deleteItem)
                    .debugDrawerButtonStyle(.destructive)
                    .accessibilityLabel("Delete Item \(title)")
            }
        }

        private var textEditor: some View {
            VStack(alignment: .leading, spacing: 0) {
                DefaultsEditorField(fieldTitle, problem: problem?.message) {
                    TextField("Value", text: $text, prompt: Text(value.type == .data ? "Bytes" : "Value"))
                        .debugDrawerFont(value.type == .string ? .body : .code)
                        .debugDrawerTextFieldStyle()
                        .autocorrectionDisabled()
                        .accessibilityLabel(name)
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(value.type == .number ? .numbersAndPunctuation : .default)
                    #endif
                } accessory: {
                    // Data's encoding sits beside the field's name, as it changes how the field
                    // reads, which leaves the row below to Save and Delete Item.
                    if value.type == .data {
                        encodingPicker
                    }
                }
                DebugDrawerActionRow {
                    Button("Save") {
                        if let parsed { save(parsed) }
                    }
                    .debugDrawerButtonStyle(.primary)
                    .disabled(parsed == nil)
                    .accessibilityLabel("Save \(name)")
                } trailing: {
                    deleteItemButton
                }
            }
        }

        private var encodingPicker: some View {
            Picker("Encoding", selection: $encoding) {
                ForEach(DataTextEncoding.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel("Data encoding")
            .accessibilityElement(children: .contain)
            .onChange(of: encoding) { previous, current in
                // The same bytes in the other encoding; text that isn't bytes stays as typed.
                if let data = try? previous.data(from: text) {
                    text = current.text(for: data)
                }
            }
        }

        /// The value the field holds; `nil` while it holds none.
        private var parsed: PropertyListValue? {
            try? value.replacement(parsing: text, encoding: encoding)
        }

        /// Why the field holds no value.
        private var problem: PropertyListTextError? {
            do {
                _ = try value.replacement(parsing: text, encoding: encoding)
                return nil
            } catch {
                return error
            }
        }
    }

    extension PropertyListValue {
        /// The value as its field starts: a string as itself, a number, data in hex.
        fileprivate var fieldText: String {
            switch self {
            case let .data(data): DataTextEncoding.hex.text(for: data)
            default: summary
            }
        }
    }
#endif
