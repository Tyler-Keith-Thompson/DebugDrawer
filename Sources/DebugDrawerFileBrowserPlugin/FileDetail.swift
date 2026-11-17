#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// A file: its name and path, what it is, its size and dates, its preview, then its actions.
    /// In the bundle it can't be renamed or deleted.
    struct FileDetail: View {
        let detail: FileDetailState
        let actions: FileBrowserActions
        @Environment(\.locale) private var locale

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                FileBrowserHeader(
                    title: detail.item.name,
                    path: detail.relativePath,
                    backTitle: detail.item.url.deletingLastPathComponent().lastPathComponent,
                    onBack: actions.back
                )
                facts
                switch detail.preview {
                case .loading:
                    DebugDrawerSection {
                        EmptyView()
                    } footer: {
                        Text("Reading the file…")
                    }
                case let .failed(reason):
                    DebugDrawerIssueRow("Couldn't read the file", severity: .error) {
                        Text(reason)
                    }
                case let .loaded(preview):
                    FilePreviewView(preview: preview, fileSize: detail.item.size)
                }
                FileItemActions(item: detail.item, canChange: !detail.root.isReadOnly, copyText: copyText, actions: actions)
            }
        }

        private var facts: some View {
            VStack(alignment: .leading, spacing: 0) {
                if case let .loaded(preview) = detail.preview {
                    DebugDrawerKeyValueRow("Kind", value: preview.kindTitle)
                        .debugDrawerValueStyle(.text)
                    if case let .image(image) = preview {
                        DebugDrawerKeyValueRow("Dimensions", value: "\(image.pixelWidth) × \(image.pixelHeight) px")
                    }
                }
                DebugDrawerKeyValueRow("Size", value: detail.item.size.byteCountText(locale))
                FileDateRows(item: detail.item)
                if detail.root.isReadOnly {
                    DebugDrawerKeyValueRow("Access", value: "Read-only")
                        .debugDrawerValueStyle(.text)
                }
            }
        }

        private var copyText: String? {
            guard case let .loaded(preview) = detail.preview else { return nil }
            return preview.text?.string
        }
    }
#endif
