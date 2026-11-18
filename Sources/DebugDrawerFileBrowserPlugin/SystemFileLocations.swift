#if DEBUG
    import DebugDrawer
    import Foundation

    /// The app's own folders, laid out under its home folder as the system lays them out, and its
    /// app groups' containers.
    ///
    /// A Mac app outside the sandbox shares Documents, Library and Application Support with every
    /// other app of the user's, so there it lists its own subfolders of Application Support and
    /// Caches (named for its bundle identifier or its executable) instead: listing all of Library
    /// would show other apps' files, and reading Documents asks the user's permission.
    struct SystemFileLocations: FileLocations {
        /// The app's home folder: its container on iOS and in the Mac's sandbox, the user's home
        /// folder outside it.
        let home: URL
        /// The app's temporary folder.
        let temporary: URL
        /// Whether the app runs in the App Sandbox, or on a platform where every app does.
        let isSandboxed: Bool
        /// The names the app's own folders of Application Support and Caches may have, first
        /// choice first: its bundle identifier, then its executable's name.
        let ownFolderNames: [String]
        let bundle: URL

        /// The app's folders under `home`.
        ///
        /// - Parameters:
        ///   - home: The app's home folder; `NSHomeDirectory()` by default.
        ///   - temporary: Its temporary folder; `NSTemporaryDirectory()` by default.
        ///   - isSandboxed: Whether its folders are its own; on the Mac, whether it runs in the App
        ///     Sandbox.
        ///   - ownFolderNames: The names its own folders of Application Support and Caches may
        ///     have, used outside the sandbox.
        ///   - bundle: Its bundle.
        init(
            home: URL = .homeDirectory,
            temporary: URL = .temporaryDirectory,
            isSandboxed: Bool = Self.isAppSandboxed,
            ownFolderNames: [String] = [Bundle.main.bundleIdentifier, ProcessInfo.processInfo.processName].compactMap(\.self),
            bundle: URL = Bundle.main.bundleURL
        ) {
            self.home = home
            self.temporary = temporary
            self.isSandboxed = isSandboxed
            self.ownFolderNames = ownFolderNames
            self.bundle = bundle
        }

        /// Documents, Library and tmp; outside the sandbox, the app's own folders of Application
        /// Support and Caches, then tmp. Each is listed whether it exists yet or not.
        var appFolders: [FileRoot] {
            let temporary = FileRoot(kind: .temporary, url: temporary)
            let library = home.appending(path: "Library", directoryHint: .isDirectory)
            guard isSandboxed else {
                let applicationSupport = library.appending(path: "Application Support", directoryHint: .isDirectory)
                let caches = library.appending(path: "Caches", directoryHint: .isDirectory)
                return [
                    FileRoot(kind: .applicationSupport, url: ownSubfolder(of: applicationSupport)),
                    FileRoot(kind: .caches, url: ownSubfolder(of: caches)),
                    temporary
                ]
            }
            let documents = home.appending(path: "Documents", directoryHint: .isDirectory)
            return [FileRoot(kind: .documents, url: documents), FileRoot(kind: .library, url: library), temporary]
        }

        func containerURL(forAppGroup identifier: String) -> URL? {
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
        }

        /// The app's own folder in a shared folder: the first of ``ownFolderNames`` that exists,
        /// or the first name when none does yet.
        private func ownSubfolder(of folder: URL) -> URL {
            let candidates = ownFolderNames.map { folder.appending(path: $0, directoryHint: .isDirectory) }
            let existing = DebugDrawerActivity.$isDrawerWork.withValue(true) {
                candidates.first { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
            }
            // An app with neither a bundle identifier nor a process name doesn't run; the folder
            // itself is still a place to look.
            return existing ?? candidates.first ?? folder
        }

        /// Whether the app runs in the App Sandbox. Every iOS, tvOS, visionOS and watchOS app does.
        static var isAppSandboxed: Bool {
            #if os(macOS)
                ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
            #else
                true
            #endif
        }
    }
#endif
