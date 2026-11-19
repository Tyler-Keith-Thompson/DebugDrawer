#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The plugin's body: the form while one is open, the list otherwise. Reads the keychain the
    /// first time it is shown.
    ///
    /// It draws ``KeychainModel``'s snapshots from its transport and sends it what the user does;
    /// Copy, which writes the clipboard, and the masking of sensitive values stay in the views.
    struct KeychainPluginView: View {
        @StateObject private var transport: DebugDrawerPluginTransport<KeychainSnapshot, KeychainCommand>
        @ObservedObject private var drawer = DebugDrawer.shared

        /// - Parameter transport: Joins the view to the model; made once, for the view's lifetime.
        init(transport: @escaping @autoclosure () -> DebugDrawerPluginTransport<KeychainSnapshot, KeychainCommand>) {
            _transport = StateObject(wrappedValue: transport())
        }

        var body: some View {
            let snapshot = transport.snapshot
            Group {
                if let editor = snapshot.editor {
                    KeychainPasswordForm(
                        editor: editor, accessGroups: snapshot.accessGroups, issue: snapshot.issue,
                        save: { send(.save($0)) }, cancel: { send(.cancelEditing) }
                    )
                } else {
                    KeychainListView(
                        items: snapshot.shownItems,
                        accessGroups: snapshot.accessGroups,
                        filter: filter,
                        selection: snapshot.selection,
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
    }

    extension KeychainContents {
        /// The keychain's refusal to be read, if it refused.
        fileprivate var failure: KeychainError? {
            if case let .unavailable(error) = self { return error }
            return nil
        }
    }
#endif
