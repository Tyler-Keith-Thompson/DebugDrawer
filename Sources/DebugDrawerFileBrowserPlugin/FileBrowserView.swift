#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The browser: the list of roots, a folder or a file, and under it why the last change
    /// failed.
    struct FileBrowserView: View {
        let screen: FileBrowserScreen
        /// The total size of each folder counted, by its path.
        let folderSizes: [String: Int64]
        /// Why the last import, rename or delete failed.
        var failure: String?
        let actions: FileBrowserActions

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                switch screen {
                case let .roots(roots):
                    FileRootList(roots: roots, folderSizes: folderSizes) { actions.open(.directory($0, $0.url)) }
                case let .directory(listing):
                    // A view per folder, so the filter starts empty in each.
                    DirectoryView(listing: listing, folderSizes: folderSizes, actions: actions)
                        .id(listing.url.filePath)
                case let .file(detail):
                    FileDetail(detail: detail, actions: actions)
                        .id(detail.item.path)
                }
                if let failure {
                    DebugDrawerIssueRow(failure, severity: .error)
                }
            }
        }
    }

    /// What the browser's buttons do.
    struct FileBrowserActions {
        /// Shows a folder or a file.
        var open: (FileBrowserPlace) -> Void = { _ in }
        /// Shows the place one step up.
        var back: () -> Void = {}
        /// Reads the place shown again.
        var refresh: () -> Void = {}
        /// Asks for a file to import into the folder shown.
        var importFile: () -> Void = {}
        /// Renames a file or folder.
        var rename: (FileItem, String) -> Void = { _, _ in }
        /// Deletes a file or folder.
        var delete: (FileItem) -> Void = { _ in }
    }
#endif
