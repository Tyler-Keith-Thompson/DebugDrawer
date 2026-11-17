#if DEBUG
    import DebugDrawer
    import SwiftUI
    #if os(macOS)
        import AppKit
    #endif

    /// The actions on the folder or file shown, in the drawer's action row.
    ///
    /// A folder offers Import… (unless read-only) and Refresh; a file offers Share. Both have a More
    /// menu of Copy Path, Copy Text for a preview that is text, Reveal in Finder for a file on the
    /// Mac, and, unless read-only, Rename…, which edits the name in place. Unless read-only, Delete
    /// trails the row and asks first, in place under it. It keeps which of those is open.
    struct FileItemActions: View {
        /// What is open under the row.
        enum Pending: Hashable {
            case none
            case renaming(String)
            case deleting
        }

        let item: FileItem
        /// Whether it may be renamed and deleted: not in the bundle, and not a root.
        let canChange: Bool
        /// Whether files may be imported into it: a folder outside the bundle.
        var canImport = false
        /// The text Copy Text copies, for a file whose preview is text.
        var copyText: String?
        let actions: FileBrowserActions
        @State var pending = Pending.none
        let inspection = Inspection<Self>()

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                DebugDrawerActionRow {
                    if item.isDirectory {
                        folderActions
                    } else {
                        fileActions
                    }
                } trailing: {
                    if canChange {
                        Button("Delete", role: .destructive) { pending = .deleting }
                            .debugDrawerButtonStyle(.destructive)
                            .disabled(pending != .none)
                            .accessibilityLabel("Delete \(item.name)")
                    }
                }
                switch pending {
                case .none:
                    EmptyView()
                case let .renaming(name):
                    renameEditor(name)
                case .deleting:
                    deleteConfirmation
                }
            }
            .onReceive(inspection.notice) { inspection.visit(self, $0) }
        }

        @ViewBuilder private var folderActions: some View {
            if canImport {
                Button("Import…", action: actions.importFile)
                    .accessibilityHint("Copies a file you pick into this folder")
            }
            Button("Refresh", action: actions.refresh)
                .accessibilityHint("Reads the folder again and counts its sizes")
            moreMenu
        }

        @ViewBuilder private var fileActions: some View {
            ShareLink(item: item.url) {
                Text("Share…")
            }
            .accessibilityLabel("Share \(item.name)")
            moreMenu
        }

        // The less frequent actions sit in one menu rather than a button each, so the row fits on
        // one line at the drawer's narrowest (316 points), with Delete still trailing. Reveal in
        // Finder is among them: as a button it pushed the Mac's row onto a second line.
        private var moreMenu: some View {
            Menu("More") {
                Button("Copy Path") { debugDrawerCopyToClipboard(item.path) }
                    .accessibilityHint("Copies to the clipboard")
                if let copyText {
                    Button("Copy Text") { debugDrawerCopyToClipboard(copyText) }
                        .accessibilityHint("Copies to the clipboard")
                }
                #if os(macOS)
                    if !item.isDirectory {
                        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
                            .accessibilityHint("Shows the file in a Finder window")
                    }
                #endif
                if canChange {
                    Divider()
                    Button("Rename…") { pending = .renaming(item.name) }
                        .disabled(pending != .none)
                        .accessibilityHint("Edits the name of \(item.name) below")
                }
            }
            .menuStyle(.button)
            .fixedSize()
            .accessibilityLabel("More")
            .accessibilityHint("Copies the path of \(item.name), or renames it")
        }

        private func renameEditor(_ name: String) -> some View {
            let binding = Binding { name } set: { pending = .renaming($0) }
            return VStack(alignment: .leading, spacing: 6) {
                TextField("Name", text: binding)
                    .debugDrawerTextFieldStyle()
                    .accessibilityLabel("New name for \(item.name)")
                    .onSubmit { rename(to: name) }
                DebugDrawerActionRow {
                    Button("Rename") { rename(to: name) }
                        .debugDrawerButtonStyle(.primary)
                        .disabled(!FileBrowserModel.isFileName(name.trimmingCharacters(in: .whitespacesAndNewlines)))
                        .accessibilityLabel("Rename to \(name)")
                    Button("Cancel") { pending = .none }
                        .accessibilityLabel("Cancel renaming")
                }
            }
            .debugDrawerRowPadding()
        }

        private var deleteConfirmation: some View {
            DebugDrawerIssueRow("Delete \(item.name)?", severity: .warning) {
                Text(item.isDirectory ? "The folder and everything in it are deleted. This can't be undone." : "This can't be undone.")
                DebugDrawerActionRow {
                    Button("Delete", role: .destructive) {
                        pending = .none
                        actions.delete(item)
                    }
                    .debugDrawerButtonStyle(.destructive)
                    .accessibilityLabel("Delete \(item.name) now")
                    Button("Cancel") { pending = .none }
                        .accessibilityLabel("Cancel deleting")
                }
            }
        }

        private func rename(to name: String) {
            pending = .none
            actions.rename(item, name)
        }
    }
#endif
