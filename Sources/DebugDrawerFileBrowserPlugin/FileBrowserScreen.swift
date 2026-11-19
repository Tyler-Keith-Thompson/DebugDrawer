#if DEBUG
    import Foundation

    /// Where the browser is: the list of roots, a folder or a file, and the root it is under.
    enum FileBrowserPlace: Hashable, Codable, Sendable {
        case roots
        case directory(FileRoot, URL)
        case file(FileRoot, FileItem)

        /// The root it is under, `nil` for the list of roots.
        var root: FileRoot? {
            switch self {
            case .roots: nil
            case let .directory(root, _), let .file(root, _): root
            }
        }

        /// One step up: a file's folder, a folder's parent, or the roots from a root.
        var parent: FileBrowserPlace {
            switch self {
            case .roots:
                .roots
            case let .directory(root, url):
                url.isSameFile(as: root.url) ? .roots : .directory(root, url.deletingLastPathComponent())
            case let .file(root, item):
                .directory(root, item.url.deletingLastPathComponent())
            }
        }
    }

    /// What the browser shows.
    enum FileBrowserScreen: Hashable, Codable, Sendable {
        /// The folders it starts from, and whether none the app can change holds anything.
        case roots(FileRoots, isEmpty: Bool)
        /// A folder and what it holds.
        case directory(DirectoryListing)
        /// A file, its facts and its preview.
        case file(FileDetailState)

        /// Where it is.
        var place: FileBrowserPlace {
            switch self {
            case .roots: .roots
            case let .directory(listing): .directory(listing.root, listing.url)
            case let .file(detail): .file(detail.root, detail.item)
            }
        }
    }

    /// A change the file system refused: what failed ("Couldn't delete old.log") and why.
    struct FileBrowserFailure: Hashable, Codable, Sendable {
        let title: String
        let reason: String
    }

    /// A read the browser waits on.
    enum Loadable<Value: Hashable & Codable & Sendable>: Hashable, Codable, Sendable {
        case loading
        case loaded(Value)
        /// The read failed, with why.
        case failed(String)
    }

    /// A folder the browser shows.
    struct DirectoryListing: Hashable, Codable, Sendable {
        let root: FileRoot
        let url: URL
        let contents: Loadable<DirectoryContents>

        /// Whether it is its root itself, which can't be renamed or deleted.
        var isRoot: Bool {
            url.isSameFile(as: root.url)
        }

        /// The folder's path from its root: "Documents/Exports/2026".
        var relativePath: String {
            root.relativePath(of: url)
        }
    }

    /// A folder, and the files and folders in it.
    struct DirectoryContents: Hashable, Codable, Sendable {
        let directory: FileItem
        let items: [FileItem]
    }

    /// A file the browser shows.
    struct FileDetailState: Hashable, Codable, Sendable {
        let root: FileRoot
        let item: FileItem
        let preview: Loadable<FilePreview>

        /// The file's path from its root: "Documents/config.json".
        var relativePath: String {
            root.relativePath(of: item.url)
        }
    }

    extension FileRoot {
        /// The path of `url`, inside this root, from the root's title.
        func relativePath(of url: URL) -> String {
            let rootPath = self.url.filePath
            let path = url.filePath
            guard path.hasPrefix(rootPath + "/") else { return title }
            return title + path.dropFirst(rootPath.count)
        }
    }
#endif
