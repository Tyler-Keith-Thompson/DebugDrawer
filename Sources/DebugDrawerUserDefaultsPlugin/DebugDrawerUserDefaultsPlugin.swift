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

        /// What Copy Value puts on the clipboard: the value's description, or the mask when the
        /// key contains a key pattern.
        func copiedValue(redaction: DebugDrawerRedaction) -> String {
            redaction.redacting(value, forKey: key)
        }
    }

    @MainActor
    final class UserDefaultsStore: ObservableObject {
        static let shared = UserDefaultsStore()

        @Published var entries: [DefaultsEntry] = []
        @Published var searchText = ""
        @Published var showSystemKeys = false

        var filteredEntries: [DefaultsEntry] {
            var result = showSystemKeys ? entries : entries.filter { !Self.isSystemKey($0.key) }
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

        /// Whether the system or a framework, not the app, wrote the key, judged by its prefix.
        static func isSystemKey(_ key: String) -> Bool {
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
        @ObservedObject private var drawer = DebugDrawer.shared
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

                ScrollViewReader { proxy in
                    DebugDrawerSearchableList("Filter...", text: $store.searchText, accessibilityLabel: "Filter keys and values") {
                        ForEach(store.filteredEntries) { entry in
                            DefaultsEntryRow(
                                entry: entry,
                                redaction: drawer.redaction,
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
                    .onChange(of: selectedKey) { _, newKey in
                        if let key = newKey {
                            withAnimation(reduceMotion ? nil : .default) {
                                proxy.scrollTo(key, anchor: .bottom)
                            }
                        }
                    }
                }
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
