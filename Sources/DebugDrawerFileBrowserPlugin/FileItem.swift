#if DEBUG
    import Foundation

    /// A file or folder, as the file system described it when it was listed.
    struct FileItem: Identifiable, Hashable, Sendable {
        let url: URL
        let isDirectory: Bool
        /// The file's size in bytes; 0 for a folder, whose total is counted apart.
        let size: Int64
        let modified: Date?
        let created: Date?

        /// Its path, so the same file keeps its identity from one listing to the next however
        /// its URL was made.
        var id: String {
            path
        }

        var name: String {
            url.lastPathComponent
        }

        /// The path, without percent encoding or a trailing slash.
        var path: String {
            url.filePath
        }

        /// The symbol beside it, from its extension: nothing is read to choose it.
        var systemImage: String {
            if isDirectory { return "folder" }
            return switch url.pathExtension.lowercased() {
            case "json": "curlybraces"
            case "plist": "list.bullet.rectangle"
            case "sqlite", "sqlite3", "db", "store": "cylinder"
            case "png", "jpg", "jpeg", "gif", "heic", "tiff", "webp": "photo"
            case "txt", "log", "md", "csv", "xml", "strings": "doc.plaintext"
            default: "doc"
            }
        }
    }

    extension URL {
        /// The path, without percent encoding or a trailing slash, so a folder's URL compares
        /// equal however it was made.
        var filePath: String {
            let path = standardizedFileURL.path(percentEncoded: false)
            return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
        }

        /// Whether both name the same file, however each was made.
        func isSameFile(as other: URL) -> Bool {
            filePath == other.filePath
        }
    }
#endif
