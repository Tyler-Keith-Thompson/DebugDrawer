#if DEBUG
    import Foundation

    /// The app's own folders, from `FileManager`, and its app groups, from its entitlements.
    ///
    /// A Mac app outside the sandbox shares Application Support and Documents with every other
    /// app of the user's, so there only its own subfolders of Application Support are searched
    /// (named for its bundle identifier and its executable), and Documents not at all: searching
    /// all of them would list other apps' stores, and reading Documents asks the user's permission.
    struct SystemStoreLocations: StoreLocations {
        var applicationSupport: URL? {
            let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            #if os(macOS)
                guard !Self.isSandboxed else { return folder }
                return folder.flatMap { Self.ownSubfolder(of: $0) }
            #else
                return folder
            #endif
        }

        var documents: URL? {
            #if os(macOS)
                guard Self.isSandboxed else { return nil }
            #endif
            return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        }

        var appGroupIdentifiers: [String] {
            AppGroupEntitlements.identifiers()
        }

        func containerURL(forAppGroup identifier: String) -> URL? {
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
        }

        #if os(macOS)
            /// Whether the app runs in the App Sandbox, whose folders are the app's own.
            private static var isSandboxed: Bool {
                ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
            }

            /// The app's own folder in a shared Application Support: the first of those named for
            /// its bundle identifier and its executable that exists.
            private static func ownSubfolder(of folder: URL) -> URL? {
                let names = [Bundle.main.bundleIdentifier, ProcessInfo.processInfo.processName].compactMap(\.self)
                return names.map { folder.appending(path: $0, directoryHint: .isDirectory) }
                    .first { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
            }
        #endif
    }
#endif
