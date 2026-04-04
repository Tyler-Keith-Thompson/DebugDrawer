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
    }

    @MainActor
    final class KeychainStore: ObservableObject {
        static let shared = KeychainStore()

        @Published var entries: [KeychainEntry] = []
        @Published var searchText = ""

        var filteredEntries: [KeychainEntry] {
            guard !searchText.isEmpty else { return entries }
            let q = searchText.lowercased()
            return entries.filter {
                $0.account.lowercased().contains(q) ||
                    $0.service.lowercased().contains(q) ||
                    ($0.label?.lowercased().contains(q) ?? false)
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
                kSecMatchLimit as String: kSecMatchLimitAll,
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
                kSecAttrAccount as String: entry.account,
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
        public var icon = "key"

        public init() {}

        public var body: some View {
            KeychainPluginView()
        }
    }

    struct KeychainPluginView: View {
        @ObservedObject private var store = KeychainStore.shared
        @State private var selectedId: UUID?
        @State private var confirmDelete: UUID?
        @State private var loaded = false

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("\(store.filteredEntries.count) items")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(loaded ? "Reload" : "Load") {
                        store.reload()
                        loaded = true
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if loaded {
                    TextField("Filter...", text: $store.searchText)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(store.filteredEntries) { entry in
                                keychainRow(entry)
                            }
                        }
                    }
                    .frame(maxHeight: 250)
                    .background(Color.black.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
        }

        private func keychainRow(_ entry: KeychainEntry) -> some View {
            let isSelected = selectedId == entry.id
            return VStack(alignment: .leading, spacing: 0) {
                Button(action: { selectedId = isSelected ? nil : entry.id }) {
                    HStack(spacing: 6) {
                        Text(entry.itemClass)
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 3)
                            .background(entry.itemClass == "Password" ? Color.green.opacity(0.15) : Color.blue.opacity(0.15))
                            .cornerRadius(2)

                        VStack(alignment: .leading, spacing: 0) {
                            Text(entry.account)
                                .font(.system(size: 10, design: .monospaced))
                                .lineLimit(1)
                            if !entry.service.isEmpty {
                                Text(entry.service)
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isSelected {
                    VStack(alignment: .leading, spacing: 4) {
                        if let label = entry.label {
                            HStack {
                                Text("Label:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(label)
                                    .font(.system(size: 10, design: .monospaced))
                            }
                        }

                        Text(entry.valuePreview)
                            .font(.system(size: 10, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.primary.opacity(0.05))
                            .cornerRadius(3)

                        HStack {
                            Button("Copy Value") {
                                if let data = entry.data, let str = String(data: data, encoding: .utf8) {
                                    debugDrawerCopyToClipboard(str)
                                }
                            }
                            .controlSize(.small)
                            .buttonStyle(.bordered)

                            Spacer()

                            if confirmDelete == entry.id {
                                Text("Sure?")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                Button("Yes") {
                                    store.deleteEntry(entry)
                                    confirmDelete = nil
                                    selectedId = nil
                                }
                                .controlSize(.small)
                                .buttonStyle(.borderedProminent)
                                .tint(.red)
                                Button("Cancel") { confirmDelete = nil }
                                    .controlSize(.small)
                                    .buttonStyle(.bordered)
                            } else {
                                Button("Delete") { confirmDelete = entry.id }
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
    }

    // MARK: - Convenience installer

    public extension DebugDrawer {
        func installKeychain() {
            registerGlobal(KeychainPlugin())
        }
    }
#endif
