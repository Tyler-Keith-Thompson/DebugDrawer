#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// A folder: its name and path, its total size, item count and dates, then what it holds,
    /// folders first, each with its size, under a filter field, then its actions. In the bundle
    /// nothing can be imported, renamed or deleted.
    struct DirectoryView: View {
        let listing: DirectoryListing
        /// The total size of each folder counted, by its path.
        let folderSizes: [String: Int64]
        let actions: FileBrowserActions
        @State private var filter = ""
        @Environment(\.locale) private var locale
        /// The tallest the list grows before it scrolls.
        @ScaledMetric(relativeTo: .body) private var listHeight: CGFloat = 280

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                FileBrowserHeader(
                    title: listing.isRoot ? listing.root.title : listing.url.lastPathComponent,
                    path: listing.relativePath,
                    backTitle: listing.isRoot ? "Locations" : listing.url.deletingLastPathComponent().lastPathComponent,
                    onBack: actions.back
                )
                switch listing.contents {
                case .loading:
                    DebugDrawerSection {
                        EmptyView()
                    } footer: {
                        Text("Reading the folder…")
                    }
                case let .failed(reason):
                    DebugDrawerIssueRow("Couldn't read the folder", severity: .error) {
                        Text(reason)
                    }
                    DebugDrawerActionRow {
                        Button("Refresh", action: actions.refresh)
                            .accessibilityHint("Reads the folder again")
                    }
                case let .loaded(contents):
                    facts(contents)
                    items(contents.items)
                    FileItemActions(
                        item: contents.directory,
                        canChange: !listing.root.isReadOnly && !listing.isRoot,
                        canImport: !listing.root.isReadOnly,
                        actions: actions
                    )
                }
            }
        }

        private func facts(_ contents: DirectoryContents) -> some View {
            VStack(alignment: .leading, spacing: 0) {
                DebugDrawerKeyValueRow("Size", value: size(of: contents.directory) ?? "Counting…")
                DebugDrawerKeyValueRow("Items", value: contents.items.count.formatted(.number.locale(locale)))
                FileDateRows(item: contents.directory)
                if listing.root.isReadOnly {
                    DebugDrawerKeyValueRow("Access", value: "Read-only")
                        .debugDrawerValueStyle(.text)
                }
            }
        }

        @ViewBuilder
        private func items(_ items: [FileItem]) -> some View {
            if items.isEmpty {
                DebugDrawerSection {
                    EmptyView()
                } footer: {
                    Text("The folder is empty.")
                }
            } else {
                let matching = items.filter { $0.matches(filter) }
                DebugDrawerSearchableList("Filter files…", text: $filter, accessibilityLabel: "Filter files by name", maxHeight: listHeight) {
                    ForEach(matching) { item in
                        FileListRow(
                            title: item.name,
                            systemImage: item.systemImage,
                            size: size(of: item),
                            hint: item.isDirectory ? "Opens the folder" : "Shows the file's details and preview"
                        ) {
                            actions.open(item.isDirectory ? .directory(listing.root, item.url) : .file(listing.root, item))
                        }
                    }
                }
                if matching.isEmpty {
                    DebugDrawerSection {
                        EmptyView()
                    } footer: {
                        Text("No files match “\(filter.trimmingCharacters(in: .whitespacesAndNewlines))”.")
                    }
                }
            }
        }

        /// A file's size, or a folder's total once counted.
        private func size(of item: FileItem) -> String? {
            (item.isDirectory ? folderSizes[item.path] : item.size)?.byteCountText(locale)
        }
    }

    extension FileItem {
        /// Whether the filter's text appears in its name, ignoring case and diacritics; blank
        /// text matches every item.
        fileprivate func matches(_ query: String) -> Bool {
            let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
            return query.isEmpty || name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
#endif
