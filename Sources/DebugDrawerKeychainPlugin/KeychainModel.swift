import Combine
import DebugDrawer
import Foundation

#if DEBUG
    // The keychain is read and changed through `Keychain`, whose `SecItem` calls answer at once,
    // so every command lands before `perform(_:)` returns: commands take effect in the order sent,
    // and the filter bound through a direct transport reads back what was typed. The model holds
    // values only; a password is read when its item is opened or edited, never by listing.

    /// The Keychain plugin's state and behavior, without its views: the app's keychain items, the
    /// filter, the open item with its password, the add or edit form and the last refusal, read as
    /// a ``KeychainSnapshot`` and changed with a ``KeychainCommand``.
    ///
    /// The plugin's view reaches it through a `DebugDrawerPluginTransport`:
    ///
    /// ```swift
    /// let transport = DebugDrawerPluginTransport.direct(to: KeychainModel.shared)
    /// ```
    ///
    /// Release builds get a stand-in whose snapshot holds nothing and which ignores every command.
    @MainActor
    public final class KeychainModel: DebugDrawerPluginModel {
        /// The model over the app's own keychain (on the Mac, the data protection keychain), which
        /// the plugin shows.
        public static let shared = KeychainModel()

        @Published private(set) var contents = KeychainContents.unread
        @Published var filter = KeychainFilter()
        @Published private(set) var selection: KeychainSelection?
        @Published private(set) var editor: KeychainEditor?
        @Published private(set) var issue: KeychainIssue?

        private let keychain: any Keychain
        /// The drawers the plugin is installed in; the last to remove it drops what was read.
        private var installations: Set<ObjectIdentifier> = []

        /// - Parameter keychain: The keychain to list, read and change.
        init(keychain: any Keychain = _Keychain()) {
            self.keychain = keychain
        }

        public var snapshot: KeychainSnapshot {
            KeychainSnapshot(contents: contents, filter: filter, selection: selection, editor: editor, issue: issue)
        }

        public func perform(_ command: KeychainCommand) {
            switch command.action {
            case .reload:
                reload()
            case let .setFilter(filter):
                self.filter = filter
            case let .toggle(id):
                withListed(id) { toggle($0) }
            case .startAdding:
                startAdding()
            case let .startEditing(id):
                withListed(id) { startEditing($0) }
            case .cancelEditing:
                cancelEditing()
            case let .save(password):
                save(password)
            case let .delete(id):
                withListed(id) { delete($0) }
            case .deleteShown:
                // The items shown now, as the user saw them when asking.
                delete(shownItems)
            }
        }

        /// Counts `drawer` as one the plugin is installed in.
        func install(in drawer: ObjectIdentifier) {
            installations.insert(drawer)
        }

        /// Uncounts `drawer`; once no drawer holds the plugin, drops the items read, the open item
        /// with its password, the form and its draft, and the last refusal, so no secret stays in
        /// memory. The filter stays.
        func uninstall(from drawer: ObjectIdentifier) {
            guard installations.remove(drawer) != nil, installations.isEmpty else { return }
            contents = .unread
            selection = nil
            editor = nil
            issue = nil
        }

        /// The items the filter lets through.
        var shownItems: [KeychainItem] {
            snapshot.shownItems
        }

        /// The access groups of every item, for the filter to choose from.
        var accessGroups: [String] {
            snapshot.accessGroups
        }

        /// Reads the items again, in class order, keeping the open item open if it is still there.
        func reload() {
            do throws(KeychainError) {
                let items = try keychain.items().inClassOrder
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
            delete([item])
        }

        /// Deletes each of `items` alone, carrying on past a refusal and reporting the first, closes
        /// the detail of any of them, then reads the items again.
        private func delete(_ items: [KeychainItem]) {
            var refusal: KeychainError?
            for item in items {
                do throws(KeychainError) {
                    try keychain.delete(item)
                } catch {
                    refusal = refusal ?? error
                }
            }
            issue = refusal.map { KeychainIssue(action: "Couldn't delete", error: $0) }
            if let open = selection?.item.id, items.contains(where: { $0.id == open }) { selection = nil }
            reload()
        }

        /// Does `body` to the listed item `id` names; a command naming an item not listed does
        /// nothing.
        private func withListed(_ id: KeychainItem.ID, _ body: (KeychainItem) -> Void) {
            if let item = snapshot.allItems.first(where: { $0.id == id }) { body(item) }
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

    extension [KeychainItem] {
        /// The items with every class's together, passwords first, each class's in the order the
        /// keychain gave them.
        fileprivate var inClassOrder: [KeychainItem] {
            // `sorted(by:)` is stable, so each class keeps the keychain's own order.
            sorted { $0.itemClass.listOrder < $1.itemClass.listOrder }
        }
    }

    extension KeychainItemClass {
        /// Where the class's items come in the list: in `allCases` order.
        fileprivate var listOrder: Int {
            Self.allCases.firstIndex(of: self) ?? Self.allCases.count
        }
    }
#else
    // The release stand-in: the same members, and nothing behind them.

    /// Release builds read no keychain: this stand-in's snapshot holds nothing, and it ignores
    /// every command.
    @MainActor
    public final class KeychainModel: DebugDrawerPluginModel {
        /// The stand-in model.
        public static let shared = KeychainModel()

        private init() {}

        /// Always empty.
        public var snapshot: KeychainSnapshot {
            KeychainSnapshot()
        }

        /// Does nothing.
        ///
        /// - Parameter command: Ignored.
        public func perform(_ command: KeychainCommand) {}
    }
#endif
