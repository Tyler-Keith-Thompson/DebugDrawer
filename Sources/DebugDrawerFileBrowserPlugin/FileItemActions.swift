#if DEBUG
    import DebugDrawer
    import SwiftUI
    #if os(macOS)
        import AppKit
    #endif

    /// The actions on the folder or file shown, in the drawer's action row.
    ///
    /// A folder offers Refresh; a file offers Share…. Beside it, an icon-only More menu
    /// (``FileItemMoreMenu``) offers Import… for a folder that takes files, Copy Path, Copy Text for
    /// a preview that is text, Reveal in Finder for a file on the Mac, and, unless read-only,
    /// Rename…, which edits the name in place, and Delete, which asks first, in place under the
    /// row. It keeps which of those is open.
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
        @ScaledMetric(relativeTo: .body) var actionGap: CGFloat = 8
        let inspection = Inspection<Self>()

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                DebugDrawerActionRow {
                    // One item in the row, so the button and More stay on one line at
                    // accessibility sizes too, where the row stacks its items.
                    HStack(spacing: actionGap) {
                        if item.isDirectory {
                            Button("Refresh", action: actions.refresh)
                                .accessibilityLabel("Refresh")
                                .accessibilityHint("Reads the folder again and counts its sizes")
                        } else {
                            ShareLink(item: item.url) {
                                Text("Share…")
                            }
                            .accessibilityLabel("Share \(item.name)")
                        }
                        moreMenu
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

        // Every action but one sits in an icon-only menu, so the row is one line at the drawer's
        // narrowest (316 points) at every text size. Refresh is the folder's visible one because
        // every folder offers it, read-only or not.
        private var moreMenu: some View {
            FileItemMoreMenu(
                name: item.name,
                importFile: item.isDirectory && canImport ? actions.importFile : nil,
                copyPath: { [path = item.path] in debugDrawerCopyToClipboard(path) },
                copyText: copyText.map { text in { debugDrawerCopyToClipboard(text) } },
                revealInFinder: revealInFinder,
                rename: canChange ? { [name = item.name] in pending = .renaming(name) } : nil,
                delete: canChange ? { pending = .deleting } : nil,
                isAsking: pending != .none
            )
        }

        /// Reveal in Finder, for a file on the Mac.
        private var revealInFinder: (() -> Void)? {
            #if os(macOS)
                guard !item.isDirectory else { return nil }
                return { [url = item.url] in NSWorkspace.shared.activateFileViewerSelecting([url]) }
            #else
                return nil
            #endif
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
