#if DEBUG
    import DebugDrawer
    import Security
    import SwiftUI

    // MARK: - Keychain model

    struct KeychainEntry: Identifiable {
        let id = UUID()
        let itemClass: String
        let account: String
        let service: String
        let label: String?
        let data: Data?

        var valuePreview: String {
            guard let data else { return "<no data>" }
            if let str = String(data: data, encoding: .utf8) {
                if str.count > 200 { return String(str.prefix(200)) + "..." }
                return str
            }
            return "<\(data.count) bytes>"
        }

        /// Whether the rules call this item's value sensitive: its account, service or label
        /// contains a key pattern.
        func isSensitive(under redaction: DebugDrawerRedaction) -> Bool {
            [account, service, label ?? ""].contains { redaction.masksKey($0) }
        }

        /// What Copy Value puts on the clipboard: the value as UTF-8 text, or the mask when the
        /// item is sensitive; nil when the value isn't text.
        func copiedValue(redaction: DebugDrawerRedaction) -> String? {
            guard let data, let value = String(data: data, encoding: .utf8) else { return nil }
            return isSensitive(under: redaction) ? DebugDrawerRedaction.mask : value
        }
    }

    @MainActor
    final class KeychainStore: ObservableObject {
        static let shared = KeychainStore()

        @Published var entries: [KeychainEntry] = []
        @Published var searchText = ""

        var filteredEntries: [KeychainEntry] {
            guard !searchText.isEmpty else { return entries }
            let query = searchText.lowercased()
            return entries.filter {
                $0.account.lowercased().contains(query) ||
                    $0.service.lowercased().contains(query) ||
                    ($0.label?.lowercased().contains(query) ?? false)
            }
        }

        private init() {}

        func reload() {
            entries = []
            queryClass(kSecClassGenericPassword, label: "Password")
            queryClass(kSecClassInternetPassword, label: "Internet")
        }

        private func queryClass(_ secClass: CFString, label: String) {
            let query: [String: Any] = [
                kSecClass as String: secClass,
                kSecReturnAttributes as String: true,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitAll
            ]

            var result: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            guard status == errSecSuccess, let items = result as? [[String: Any]] else { return }

            for item in items {
                let entry = KeychainEntry(
                    itemClass: label,
                    account: item[kSecAttrAccount as String] as? String ?? "",
                    service: item[kSecAttrService as String] as? String ?? "",
                    label: item[kSecAttrLabel as String] as? String,
                    data: item[kSecValueData as String] as? Data
                )
                entries.append(entry)
            }
        }

        func deleteEntry(_ entry: KeychainEntry) {
            let secClass: CFString = entry.itemClass == "Internet" ? kSecClassInternetPassword : kSecClassGenericPassword
            var query: [String: Any] = [
                kSecClass as String: secClass,
                kSecAttrAccount as String: entry.account
            ]
            if !entry.service.isEmpty {
                query[kSecAttrService as String] = entry.service
            }
            SecItemDelete(query as CFDictionary)
            reload()
        }
    }

    // MARK: - Plugin

    public struct KeychainPlugin: DebugDrawerPlugin {
        public var title = "Keychain"
        public var category = "Storage"
        public var icon = "key"

        public init() {}

        public var body: some View {
            KeychainPluginView()
        }
    }

    struct KeychainPluginView: View {
        @ObservedObject private var store = KeychainStore.shared
        @ObservedObject private var drawer = DebugDrawer.shared
        @State private var selectedId: UUID?
        @State private var loaded = false

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("\(store.filteredEntries.count) items")
                        .debugDrawerFont(.secondary)
                        .debugDrawerForegroundStyle(.secondary)
                    Spacer()
                    Button(loaded ? "Reload" : "Load") {
                        store.reload()
                        loaded = true
                    }
                    .debugDrawerButtonStyle(.secondary)
                }

                if loaded {
                    DebugDrawerSearchableList("Filter...", text: $store.searchText, accessibilityLabel: "Filter keychain items") {
                        ForEach(store.filteredEntries) { entry in
                            KeychainRow(
                                entry: entry,
                                redaction: drawer.redaction,
                                isSelected: selectedId == entry.id,
                                onSelect: { selectedId = selectedId == entry.id ? nil : entry.id },
                                onDelete: {
                                    store.deleteEntry(entry)
                                    selectedId = nil
                                }
                            )
                        }
                    }
                }
            }
        }
    }

    /// A keychain item's class, account and service; selected, it shows the value, with buttons to
    /// copy it and to delete the item.
    struct KeychainRow: View {
        let entry: KeychainEntry
        let redaction: DebugDrawerRedaction
        let isSelected: Bool
        let onSelect: () -> Void
        let onDelete: () -> Void
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Button(action: onSelect) {
                    summary
                }
                .debugDrawerButtonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])

                if isSelected {
                    KeychainEntryDetail(entry: entry, redaction: redaction, onDelete: onDelete)
                }
            }
        }

        // The account and service in the drawer's code type, the item's class after them in
        // tertiary text; at accessibility text sizes the class sits below them. Each keeps to one
        // line cut in the middle, as the UserDefaults keys do, until the item is selected.
        private var summary: some View {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                : AnyLayout(HStackLayout(spacing: 6))
            return layout {
                VStack(alignment: .leading, spacing: 0) {
                    Text(entry.account)
                        .debugDrawerFont(.code)
                        .debugDrawerForegroundStyle(.primary)
                        .lineLimit(isSelected ? nil : 1)
                        .truncationMode(.middle)
                        .help(entry.account)
                    if !entry.service.isEmpty {
                        Text(entry.service)
                            .debugDrawerFont(.code)
                            .debugDrawerForegroundStyle(.tertiary)
                            .lineLimit(isSelected ? nil : 1)
                            .truncationMode(.middle)
                            .help(entry.service)
                    }
                }

                if !dynamicTypeSize.isAccessibilitySize {
                    Spacer()
                }

                Text(entry.itemClass)
                    .debugDrawerFont(.secondary)
                    .debugDrawerForegroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .debugDrawerRowPadding()
            .contentShape(Rectangle())
        }
    }

    /// A selected keychain item's label and value, with buttons to copy the value and to delete
    /// the item, which asks first. A sensitive value is masked in the copy, and on screen until
    /// revealed.
    struct KeychainEntryDetail: View {
        let entry: KeychainEntry
        let redaction: DebugDrawerRedaction
        let onDelete: () -> Void
        @State private var isConfirmingDelete = false

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                if let label = entry.label {
                    // The item's label is an identifier the app chose, even when it is a word.
                    DebugDrawerKeyValueRow("Label", value: label)
                        .debugDrawerValueStyle(.code)
                }

                DebugDrawerCodeBlock {
                    RedactedText(
                        entry.valuePreview,
                        redacted: entry.isSensitive(under: redaction) ? DebugDrawerRedaction.mask : entry.valuePreview
                    )
                }

                DebugDrawerActionRow {
                    DebugDrawerCopyButton("Copy Value") { entry.copiedValue(redaction: redaction) }
                } trailing: {
                    if isConfirmingDelete {
                        confirmation
                    } else {
                        Button("Delete", role: .destructive) { isConfirmingDelete = true }
                            .debugDrawerButtonStyle(.destructive)
                    }
                }
            }
            .padding(.bottom, 4)
        }

        private var confirmation: some View {
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
                .accessibilityLabel("Delete \(entry.account)")
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Delete \(entry.account)?")
        }
    }

    // MARK: - Convenience installer

    public extension DebugDrawer {
        func installKeychain() {
            registerGlobal(KeychainPlugin())
        }
    }
#endif
