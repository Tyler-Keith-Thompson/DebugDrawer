#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The folders the browser starts from, each with its path and the total size of what it
    /// holds, then the app groups that have no container. Above them, when none the app can
    /// change holds anything, an empty state says so.
    struct FileRootList: View {
        let roots: FileRoots
        /// Whether no root the app can change holds anything.
        var isEmpty = false
        /// The total size of each folder counted, by its path.
        let folderSizes: [String: Int64]
        let onOpen: (FileRoot) -> Void
        @Environment(\.locale) private var locale

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                if isEmpty {
                    DebugDrawerEmptyState("No files yet", systemImage: "folder") {
                        Text("The app's folders are empty. Files it writes show here.")
                    }
                }
                DebugDrawerSection("Locations") {
                    ForEach(roots.available) { root in
                        FileListRow(
                            title: root.title,
                            systemImage: root.systemImage,
                            size: folderSizes[root.url.filePath]?.byteCountText(locale),
                            detail: root.url.filePath,
                            hint: root.isReadOnly ? "Opens the folder, read-only" : "Opens the folder"
                        ) { onOpen(root) }
                    }
                } footer: {
                    Text("Sizes count every file inside, at any depth. The app bundle is read-only.")
                }
                ForEach(roots.missingAppGroups, id: \.self) { identifier in
                    DebugDrawerIssueRow("No container for \(identifier)", severity: .warning) {
                        Text("The system gives the app no container for this group. Check that its entitlements name it.")
                    }
                }
            }
        }
    }
#endif
