#if DEBUG
    import DebugDrawer
    import SwiftUI

    // MARK: - UserDefaults model

    struct DefaultsEntry: Identifiable {
        let id: String
        let key: String
        let value: String
        let type: String
        let rawValue: Any
    }

    @MainActor
    final class UserDefaultsStore: ObservableObject {
        static let shared = UserDefaultsStore()

        @Published var entries: [DefaultsEntry] = []
        @Published var searchText = ""
        @Published var showSystemKeys = false

        var filteredEntries: [DefaultsEntry] {
            var result = showSystemKeys ? entries : entries.filter { !isSystemKey($0.key) }
            if !searchText.isEmpty {
                let query = searchText.lowercased()
                result = result.filter {
                    $0.key.lowercased().contains(query) || $0.value.lowercased().contains(query)
                }
            }
            return result
        }

        private static let systemPrefixes = [
            "NS", "Apple", "AK", "com.apple.", "WebKit",
            "Country", "AddressBook", "PKLog", "INNext",
            "METAL_", "MTL", "CTDirtyCount"
        ]

        private func isSystemKey(_ key: String) -> Bool {
            Self.systemPrefixes.contains(where: { key.hasPrefix($0) })
        }

        private init() {
            reload()
        }

        func reload() {
            let dict = UserDefaults.standard.dictionaryRepresentation()
            entries = dict.keys.sorted().map { key in
                let val = dict[key]!
                return DefaultsEntry(
                    id: key,
                    key: key,
                    value: describeValue(val),
                    type: typeLabel(val),
                    rawValue: val
                )
            }
        }

        func deleteKey(_ key: String) {
            UserDefaults.standard.removeObject(forKey: key)
            reload()
        }

        func setValue(_ key: String, _ value: Any) {
            UserDefaults.standard.set(value, forKey: key)
            reload()
        }

        private func describeValue(_ value: Any) -> String {
            switch value {
            case let string as String: return string
            case let number as NSNumber:
                if CFBooleanGetTypeID() == CFGetTypeID(number) {
                    return number.boolValue ? "true" : "false"
                }
                return number.stringValue
            case let date as Date: return date.formatted()
            case let data as Data: return "<Data: \(data.count) bytes>"
            case let arr as [Any]: return "[\(arr.count) items]"
            case let dict as [String: Any]: return "{\(dict.count) keys}"
            default: return String(describing: value)
            }
        }

        private func typeLabel(_ value: Any) -> String {
            switch value {
            case is String: return "String"
            case let number as NSNumber:
                if CFBooleanGetTypeID() == CFGetTypeID(number) { return "Bool" }
                if number === kCFBooleanTrue || number === kCFBooleanFalse { return "Bool" }
                return "Number"
            case is Date: return "Date"
            case is Data: return "Data"
            case is [Any]: return "Array"
            case is [String: Any]: return "Dict"
            default: return String(describing: type(of: value))
            }
        }
    }

    // MARK: - Plugin

    public struct UserDefaultsPlugin: DebugDrawerPlugin {
        public var title = "UserDefaults"
        public var category = "Storage"
        public var icon = "cylinder.split.1x2"

        public init() {}

        public var body: some View {
            UserDefaultsPluginView()
        }
    }

    struct UserDefaultsPluginView: View {
        @ObservedObject private var store = UserDefaultsStore.shared
        @State private var selectedKey: String?
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("\(store.filteredEntries.count) keys")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Toggle("System", isOn: $store.showSystemKeys)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                    Button("Reload") { store.reload() }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }

                TextField("Filter...", text: $store.searchText)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .accessibilityLabel("Filter keys and values")

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(store.filteredEntries) { entry in
                                DefaultsEntryRow(
                                    entry: entry,
                                    isSelected: selectedKey == entry.key,
                                    onSelect: { selectedKey = selectedKey == entry.key ? nil : entry.key },
                                    onSet: { value in
                                        store.setValue(entry.key, value)
                                        selectedKey = nil
                                    },
                                    onDelete: {
                                        store.deleteKey(entry.key)
                                        selectedKey = nil
                                    }
                                )
                                .id(entry.key)
                            }
                        }
                    }
                    .onChange(of: selectedKey) { _, newKey in
                        if let key = newKey {
                            withAnimation(reduceMotion ? nil : .default) {
                                proxy.scrollTo(key, anchor: .bottom)
                            }
                        }
                    }
                }
                .frame(maxHeight: 250)
                .background(Color.black.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
    }

    /// A key and its value's type; selected, it shows the value, controls to change it (Bool,
    /// String and Number values) and a button to delete the key, which asks first.
    struct DefaultsEntryRow: View {
        let entry: DefaultsEntry
        let isSelected: Bool
        let onSelect: () -> Void
        let onSet: (Any) -> Void
        let onDelete: () -> Void
        @State private var editValue: String
        @State private var isConfirmingDelete = false

        init(
            entry: DefaultsEntry,
            isSelected: Bool,
            onSelect: @escaping () -> Void,
            onSet: @escaping (Any) -> Void,
            onDelete: @escaping () -> Void
        ) {
            self.entry = entry
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
                        Text(entry.value)
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.primary.opacity(0.05))
                            .cornerRadius(3)

                        editControls

                        HStack {
                            Spacer()
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

        private var summary: some View {
            HStack(spacing: 4) {
                Text(entry.key)
                    .font(.system(.caption2, design: .monospaced))
                    .lineLimit(3)
                    .truncationMode(.middle)

                Spacer()

                Text(entry.type)
                    .font(.system(.caption2, design: .monospaced, weight: .medium))
                    .padding(.horizontal, 3)
                    .background(typeColor(entry.type).opacity(0.15))
                    .cornerRadius(2)
            }
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

    // MARK: - Convenience installer

    public extension DebugDrawer {
        func installUserDefaults() {
            registerGlobal(UserDefaultsPlugin())
        }
    }
#endif
