#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// A key to add and its value's type, which it starts at the empty value of. A key that is
    /// already taken says so below the field, and Add waits for a free one. It also adds an item to
    /// an array, which takes no key.
    struct DefaultsAddKeyForm: View {
        /// The keys already taken; `nil` for an array's item, which takes no key.
        let existingKeys: Set<String>?
        let cancel: () -> Void
        /// Adds the key, empty for an array's item, with a value of the type.
        let add: (String, PropertyListType) -> Void
        @State private var key = ""
        @State private var type = PropertyListType.string
        let inspection = Inspection<Self>()

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                if existingKeys != nil {
                    DefaultsEditorField("Key", problem: keyProblem) {
                        TextField("Key", text: $key, prompt: Text("New key"))
                            .debugDrawerFont(.code)
                            .debugDrawerTextFieldStyle()
                            .autocorrectionDisabled()
                            .accessibilityLabel("New key")
                        #if os(iOS)
                            .textInputAutocapitalization(.never)
                        #endif
                    }
                }
                DefaultsEditorField("Type") {
                    Picker("Type", selection: $type) {
                        ForEach(PropertyListType.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityLabel("Type")
                }
                DebugDrawerActionRow {
                    Button("Add") { add(existingKeys == nil ? "" : key, type) }
                        .debugDrawerButtonStyle(.primary)
                        .disabled(!canAdd)
                        .accessibilityLabel(existingKeys == nil ? "Add the item" : "Add the key")
                    Button("Cancel", action: cancel)
                        .accessibilityLabel("Cancel adding")
                }
            }
            .onReceive(inspection.notice) { inspection.visit(self, $0) }
        }

        /// Whether the fields name something to add: always for an item, and a key not taken.
        private var canAdd: Bool {
            guard let existingKeys else { return true }
            return !key.isEmpty && !existingKeys.contains(key)
        }

        /// Why the key can't be added; nothing for an empty one, which Add waits on silently.
        private var keyProblem: String? {
            guard let existingKeys, existingKeys.contains(key) else { return nil }
            return "“\(key)” is already a key here."
        }
    }
#endif
