#if DEBUG
    import Combine
    import Foundation

    /// What the plugin knows of the keychain.
    enum KeychainContents: Hashable, Sendable {
        /// Not read yet.
        case unread
        /// The items the app can read.
        case items([KeychainItem])
        /// The keychain refused to be read, as an unsigned Mac app's is.
        case unavailable(KeychainError)
    }

    /// The item whose detail is open, with its password as read when it was opened.
    struct KeychainSelection: Hashable, Sendable {
        let item: KeychainItem
        /// The password; `nil` for an item that holds none, or a failure to read it.
        let value: Result<Data?, KeychainError>
    }

    /// The add and edit form, while it is open.
    enum KeychainEditor: Hashable, Sendable {
        /// Adding a generic password, starting from the values given.
        case adding(GenericPassword)
        /// Editing `item`, starting from its values.
        case editing(KeychainItem, GenericPassword)

        /// What the form starts from.
        var draft: GenericPassword {
            switch self {
            case let .adding(draft), let .editing(_, draft): draft
            }
        }
    }

    /// A change the keychain refused, as the plugin reports it.
    struct KeychainIssue: Hashable, Sendable {
        /// What was being done ("Couldn't save").
        let action: String
        let error: KeychainError

        var message: String {
            "\(action): \(error.message)"
        }
    }

    /// The keychain plugin's state: the items, the filter, the open item and form, and the changes
    /// made through it.
    @MainActor
    final class KeychainModel: ObservableObject {
        @Published private(set) var contents = KeychainContents.unread
        @Published var filter = KeychainFilter()
        @Published private(set) var selection: KeychainSelection?
        @Published private(set) var editor: KeychainEditor?
        @Published private(set) var issue: KeychainIssue?

        private let keychain: any Keychain

        init(keychain: any Keychain) {
            self.keychain = keychain
        }

        /// The items the filter lets through.
        var shownItems: [KeychainItem] {
            guard case let .items(items) = contents else { return [] }
            return filter.apply(to: items)
        }

        /// The access groups of every item, for the filter to choose from.
        var accessGroups: [String] {
            guard case let .items(items) = contents else { return [] }
            return items.accessGroups
        }

        /// Reads the items again, keeping the open item open if it is still there.
        func reload() {
            do throws(KeychainError) {
                let items = try keychain.items()
                contents = .items(items)
                if let open = selection?.item {
                    selection = items.first { $0.id == open.id }.map(selected)
                }
            } catch {
                contents = .unavailable(error)
                selection = nil
            }
        }

        /// Opens `item`'s detail, reading its password, or closes it if it is open.
        func toggle(_ item: KeychainItem) {
            selection = selection?.item.id == item.id ? nil : selected(item)
        }

        /// Opens the form to add a generic password, in the group the filter shows.
        func startAdding() {
            issue = nil
            editor = .adding(GenericPassword(accessGroup: filter.accessGroup))
        }

        /// Opens the form to edit `item`, starting from its values and password. When the password
        /// can't be read the form stays closed and the refusal is reported, since saving a form
        /// that started empty would overwrite the password.
        func startEditing(_ item: KeychainItem) {
            do throws(KeychainError) {
                let value = try keychain.value(of: item)
                issue = nil
                editor = .editing(item, GenericPassword(editing: item, value: value))
            } catch {
                issue = KeychainIssue(action: "Couldn't read the password", error: error)
            }
        }

        /// Closes the form without saving.
        func cancelEditing() {
            editor = nil
        }

        /// Writes the form's `password`: adds it, or rewrites the item being edited. The form
        /// closes on success and stays open with the keychain's refusal otherwise.
        func save(_ password: GenericPassword) {
            guard let editor else { return }
            do throws(KeychainError) {
                switch editor {
                case .adding:
                    try keychain.add(password)
                case let .editing(item, _):
                    try keychain.update(item, to: password)
                }
                self.editor = nil
                issue = nil
                reload()
            } catch {
                issue = KeychainIssue(action: "Couldn't save", error: error)
            }
        }

        /// Deletes `item` alone, and closes its detail.
        func delete(_ item: KeychainItem) {
            do throws(KeychainError) {
                try keychain.delete(item)
                issue = nil
            } catch {
                issue = KeychainIssue(action: "Couldn't delete", error: error)
            }
            if selection?.item.id == item.id { selection = nil }
            reload()
        }

        private func selected(_ item: KeychainItem) -> KeychainSelection {
            let value: Result<Data?, KeychainError>
            do throws(KeychainError) {
                value = try .success(keychain.value(of: item))
            } catch {
                value = .failure(error)
            }
            return KeychainSelection(item: item, value: value)
        }
    }
#endif
