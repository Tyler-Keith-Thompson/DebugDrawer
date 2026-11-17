#if DEBUG
    import Foundation

    /// The app's own folders, from `FileManager`, and its app groups' containers.
    ///
    /// A Mac app outside the sandbox shares Documents, Library and Application Support with every
    /// other app of the user's, so there it lists its own subfolders of Application Support and
    /// Caches (named for its bundle identifier or its executable) instead: listing all of Library
    /// would show other apps' files, and reading Documents asks the user's permission.
    struct SystemFileLocations: FileLocations {
        var appFolders: [FileRoot] {
            let temporary = FileRoot(kind: .temporary, url: URL.temporaryDirectory)
            #if os(macOS)
                guard Self.isSandboxed else {
                    let own = [
                        Self.ownSubfolder(of: URL.applicationSupportDirectory).map { FileRoot(kind: .applicationSupport, url: $0) },
                        Self.ownSubfolder(of: URL.cachesDirectory).map { FileRoot(kind: .caches, url: $0) }
                    ]
                    return own.compactMap(\.self) + [temporary]
                }
            #endif
            return [
                FileRoot(kind: .documents, url: URL.documentsDirectory),
                FileRoot(kind: .library, url: URL.libraryDirectory),
                temporary
            ]
        }

        var bundle: URL {
            Bundle.main.bundleURL
        }

        func containerURL(forAppGroup identifier: String) -> URL? {
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
        }

        #if os(macOS)
            /// Whether the app runs in the App Sandbox, whose folders are the app's own.
            private static var isSandboxed: Bool {
                ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
            }

            /// The app's own folder in a shared folder: the first of those named for its bundle
            /// identifier and its executable that exists.
            private static func ownSubfolder(of folder: URL) -> URL? {
                let names = [Bundle.main.bundleIdentifier, ProcessInfo.processInfo.processName].compactMap(\.self)
                return names.map { folder.appending(path: $0, directoryHint: .isDirectory) }
                    .first { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
            }
        #endif
    }
#endif
