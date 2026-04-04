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
                let q = searchText.lowercased()
                result = result.filter {
                    $0.key.lowercased().contains(q) || $0.value.lowercased().contains(q)
                }
            }
            return result
        }

        private static let systemPrefixes = [
            "NS", "Apple", "AK", "com.apple.", "WebKit",
            "Country", "AddressBook", "PKLog", "INNext",
            "METAL_", "MTL", "CTDirtyCount",
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
            case let s as String: return s
            case let n as NSNumber:
                if CFBooleanGetTypeID() == CFGetTypeID(n) {
                    return n.boolValue ? "true" : "false"
                }
                return n.stringValue
            case let d as Date: return d.formatted()
            case let data as Data: return "<Data: \(data.count) bytes>"
            case let arr as [Any]: return "[\(arr.count) items]"
            case let dict as [String: Any]: return "{\(dict.count) keys}"
            default: return String(describing: value)
            }
        }

        private func typeLabel(_ value: Any) -> String {
            switch value {
            case is String: return "String"
            case let n as NSNumber:
                if CFBooleanGetTypeID() == CFGetTypeID(n) { return "Bool" }
                if n === kCFBooleanTrue || n === kCFBooleanFalse { return "Bool" }
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
        public var icon = "cylinder.split.1x2"

        public init() {}

        public var body: some View {
            UserDefaultsPluginView()
        }
    }

    struct UserDefaultsPluginView: View {
        @ObservedObject private var store = UserDefaultsStore.shared
        @State private var selectedKey: String?
        @State private var editValue = ""
        @State private var confirmDelete: String?

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

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(store.filteredEntries) { entry in
                                entryRow(entry)
                                    .id(entry.key)
                            }
                        }
                    }
                    .onChange(of: selectedKey) { _, newKey in
                        if let key = newKey {
                            withAnimation {
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

        private func entryRow(_ entry: DefaultsEntry) -> some View {
            let isSelected = selectedKey == entry.key
            return VStack(alignment: .leading, spacing: 2) {
                Button(action: {
                    selectedKey = isSelected ? nil : entry.key
                    editValue = entry.value
                }) {
                    HStack(spacing: 4) {
                        Text(entry.key)
                            .font(.system(size: 10, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer()

                        Text(entry.type)
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 3)
                            .background(typeColor(entry.type).opacity(0.15))
                            .cornerRadius(2)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isSelected {
                    VStack(alignment: .leading, spacing: 4) {
                        // Current value
                        Text(entry.value)
                            .font(.system(size: 10, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.primary.opacity(0.05))
                            .cornerRadius(3)

                        // Edit controls
                        editControls(entry)

                        // Delete
                        HStack {
                            Spacer()
                            if confirmDelete == entry.key {
                                Text("Sure?")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                Button("Yes") {
                                    store.deleteKey(entry.key)
                                    confirmDelete = nil
                                    selectedKey = nil
                                }
                                .controlSize(.small)
                                .buttonStyle(.borderedProminent)
                                .tint(.red)
                                Button("Cancel") { confirmDelete = nil }
                                    .controlSize(.small)
                                    .buttonStyle(.bordered)
                            } else {
                                Button("Delete") { confirmDelete = entry.key }
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
        }

        @ViewBuilder
        private func editControls(_ entry: DefaultsEntry) -> some View {
            switch entry.type {
            case "Bool":
                HStack {
                    Text("Value:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker(selection: boolBinding(for: entry.key, current: entry.rawValue as? NSNumber)) {
                        Text("true").tag(true)
                        Text("false").tag(false)
                    } label: { EmptyView() }
                        .pickerStyle(.segmented)
                        .controlSize(.small)
                        .frame(width: 120)
                }

            case "String":
                HStack {
                    TextField("New value", text: $editValue)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                    Button("Set") {
                        store.setValue(entry.key, editValue)
                        selectedKey = nil
                    }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                }

            case "Number":
                HStack {
                    TextField("New value", text: $editValue)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                    Button("Set") {
                        if let d = Double(editValue) {
                            store.setValue(entry.key, d)
                        } else if let i = Int(editValue) {
                            store.setValue(entry.key, i)
                        }
                        selectedKey = nil
                    }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                }

            default:
                Text("Editing not supported for \(entry.type)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }

        private func boolBinding(for key: String, current: NSNumber?) -> Binding<Bool> {
            Binding(
                get: { current?.boolValue ?? false },
                set: { store.setValue(key, $0) }
            )
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
