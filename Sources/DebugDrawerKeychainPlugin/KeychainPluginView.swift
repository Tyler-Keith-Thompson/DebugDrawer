#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The plugin's body: the form while one is open, the list otherwise. Reads the keychain the
    /// first time it is shown.
    ///
    /// It draws ``KeychainModel``'s snapshots from its transport and sends it what the user does;
    /// Copy, which writes the clipboard, and the masking of sensitive values stay in the views. The
    /// snapshot holds no password, so the open item's and the edit form's come from the model in
    /// this process, by `revealedValue`.
    struct KeychainPluginView: View {
        @StateObject private var transport: DebugDrawerPluginTransport<KeychainSnapshot, KeychainCommand>
        @ObservedObject private var drawer = DebugDrawer.shared
        /// The password read for an item, from the model in this process; the snapshot holds none.
        private let revealedValue: @MainActor (KeychainItem.ID) -> Data?

        /// - Parameters:
        ///   - transport: Joins the view to the model; made once, for the view's lifetime.
        ///   - revealedValue: The password the model read for an item, in the app's process
        ///     (`KeychainModel.revealedValue(for:)`); it changes as the transport announces.
        init(
            transport: @escaping @autoclosure () -> DebugDrawerPluginTransport<KeychainSnapshot, KeychainCommand>,
            revealedValue: @escaping @MainActor (KeychainItem.ID) -> Data?
        ) {
            _transport = StateObject(wrappedValue: transport())
            self.revealedValue = revealedValue
        }

        var body: some View {
            let snapshot = transport.snapshot
            Group {
                if let editor = snapshot.editor {
                    KeychainPasswordForm(
                        editor: revealed(editor), accessGroups: snapshot.accessGroups, issue: snapshot.issue,
                        save: { send(.save($0)) }, cancel: { send(.cancelEditing) }
                    )
                } else {
                    KeychainListView(
                        items: snapshot.shownItems,
                        accessGroups: snapshot.accessGroups,
                        filter: filter,
                        selection: snapshot.selection.map(revealed),
                        failure: snapshot.contents.failure,
                        issue: snapshot.issue,
                        redaction: drawer.redaction,
                        actions: KeychainListActions(
                            select: { send(.toggle($0.id)) }, edit: { send(.startEditing($0.id)) }, delete: { send(.delete($0.id)) },
                            add: { send(.startAdding) }, reload: { send(.reload) }
                        )
                    )
                }
            }
            .onAppear {
                if transport.snapshot.contents == .unread { send(.reload) }
            }
        }

        /// The filter, read from the snapshot and changed through the model.
        private var filter: Binding<KeychainFilter> {
            Binding(
                get: { transport.snapshot.filter },
                set: { send(.setFilter($0)) }
            )
        }

        private func send(_ action: KeychainCommand.Action) {
            transport.send(KeychainCommand(action))
        }

        /// The open item with the password the model holds for it, as the detail shows it.
        private func revealed(_ open: KeychainOpenItem) -> KeychainSelection {
            let value: Result<Data?, KeychainError> = switch open.value {
            case .held: .success(revealedValue(open.item.id))
            case .empty: .success(nil)
            case let .refused(error): .failure(error)
            }
            return KeychainSelection(item: open.item, value: value)
        }

        /// The form starting from the password the model read for the item being edited; an added
        /// password starts empty.
        private func revealed(_ editor: KeychainEditor) -> KeychainEditor {
            guard case let .editing(item, _) = editor else { return editor }
            let value = revealedValue(item.id).flatMap { String(data: $0, encoding: .utf8) } ?? ""
            return editor.starting(withValue: value)
        }
    }

    extension KeychainContents {
        /// The keychain's refusal to be read, if it refused.
        fileprivate var failure: KeychainError? {
            if case let .unavailable(error) = self { return error }
            return nil
        }
    }
#endif
