#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The plugin's body: the form while one is open, the list otherwise. Reads the keychain the
    /// first time it is shown.
    struct KeychainPluginView: View {
        @ObservedObject var model: KeychainModel
        @ObservedObject private var drawer = DebugDrawer.shared

        var body: some View {
            Group {
                if let editor = model.editor {
                    KeychainPasswordForm(
                        editor: editor, accessGroups: model.accessGroups, issue: model.issue,
                        save: model.save, cancel: model.cancelEditing
                    )
                } else {
                    KeychainListView(
                        items: model.shownItems,
                        accessGroups: model.accessGroups,
                        filter: $model.filter,
                        selection: model.selection,
                        failure: model.contents.failure,
                        issue: model.issue,
                        redaction: drawer.redaction,
                        actions: KeychainListActions(
                            select: model.toggle, edit: model.startEditing, delete: model.delete,
                            add: model.startAdding, reload: model.reload
                        )
                    )
                }
            }
            .onAppear {
                if model.contents == .unread { model.reload() }
            }
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
