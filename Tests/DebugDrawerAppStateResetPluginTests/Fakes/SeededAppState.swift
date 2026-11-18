#if DEBUG
    import Foundation
    @testable import DebugDrawerAppStateResetPlugin

    /// An app's state to reset, as fixture data: a container laid out in a temporary directory,
    /// with DebugDrawer's own files, a link out of it and an app group, and fakes for the other
    /// seams, each holding something of every kind.
    ///
    /// ```
    /// Documents/notes.txt, Documents/Drafts/a.txt, Documents/DebugDrawer Export.txt
    /// Application Support/com.example.app/store.sqlite
    /// Application Support/com.example.app/DebugDrawer Crash Reports/r1.json
    /// Application Support/link-out -> Outside
    /// tmp/scratch.tmp
    /// Caches/thumbs/1.png, Caches/DebugDrawer/Recordings/a.mov
    /// group/Library/Preferences/group.plist, group/Library/Caches/g.cache
    /// group/Library/Other/x, group/Shared/y.txt
    /// Outside/secret.txt
    /// ```
    @MainActor
    struct SeededAppState {
        /// Counts the app cleanup's runs.
        @MainActor
        final class CleanupCounter {
            var runs = 0
        }

        /// The temporary directory that holds the container, and `Outside`.
        let root: URL
        // Resolved once: resolving costs a file-system lookup per path component, and the tests ask
        // for many relative paths per seeded state.
        /// `root`'s path with its links resolved, the form the file walks report paths in.
        let resolvedRoot: String
        let preferences: FakePreferenceStore
        let keychain: FakeKeychain
        let cookies: FakeCookieStore
        let responseCache: FakeResponseCache
        let cleanupCounter: CleanupCounter
        let appState: AppState

        static let appDomain = "com.example.app"
        static let groupDomain = "group.com.example"

        /// Lays the container out in a new temporary directory.
        ///
        /// - Parameter cleanupError: What the app's cleanup throws; `nil` for one that succeeds.
        init(cleanupError: (any Error & Sendable)? = nil) throws {
            root = FileManager.default.temporaryDirectory.appending(path: "AppStateReset-\(UUID().uuidString)", directoryHint: .isDirectory)
            let files: [String: String] = [
                "Documents/notes.txt": "notes",
                "Documents/Drafts/a.txt": "abc",
                "Documents/DebugDrawer Export.txt": "export",
                "Application Support/com.example.app/store.sqlite": "0123456789",
                "Application Support/com.example.app/DebugDrawer Crash Reports/r1.json": "{}",
                "tmp/scratch.tmp": "scratch",
                "Caches/thumbs/1.png": "png",
                "Caches/DebugDrawer/Recordings/a.mov": "movie",
                "group/Library/Preferences/group.plist": "plist",
                "group/Library/Caches/g.cache": "cache",
                "group/Library/Other/x": "x",
                "group/Shared/y.txt": "y",
                "Outside/secret.txt": "secret"
            ]
            for (path, contents) in files {
                let url = root.appending(path: path)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(contents.utf8).write(to: url)
            }
            try FileManager.default.createSymbolicLink(
                at: root.appending(path: "Application Support/link-out"), withDestinationURL: root.appending(path: "Outside")
            )
            resolvedRoot = root.resolvingSymlinksInPath().path(percentEncoded: false)
            let group = root.appending(path: "group")
            let container = AppContainer(
                files: [
                    FileArea(name: "Documents", directory: root.appending(path: "Documents")),
                    FileArea(name: "Application Support", directory: root.appending(path: "Application Support")),
                    FileArea(name: "tmp", directory: root.appending(path: "tmp")),
                    FileArea(name: Self.groupDomain, directory: group)
                ],
                caches: [
                    FileArea(name: "Caches", directory: root.appending(path: "Caches")),
                    FileArea(name: "\(Self.groupDomain)/Library/Caches", directory: group.appending(path: "Library/Caches"))
                ],
                kept: [group.appending(path: "Library/Preferences"), group.appending(path: "Library/Caches")],
                appFolderName: Self.appDomain
            )
            preferences = FakePreferenceStore([
                Self.appDomain: ["onboarded", "counter", "com.debugdrawer.layout"],
                Self.groupDomain: ["shared"]
            ])
            keychain = FakeKeychain([
                FakeKeychain.password(service: "api.example.com", account: "alice"),
                FakeKeychain.password(service: "refresh", account: "alice"),
                KeychainItem(itemClass: .key, service: nil, account: nil, label: "Signing key", persistentReference: Data("key".utf8))
            ])
            cookies = FakeCookieStore([
                StoredCookie(store: .http, name: "session", domain: "example.com", path: "/"),
                StoredCookie(store: .http, name: "theme", domain: "example.com", path: "/"),
                StoredCookie(store: .web, name: "tracking", domain: "other.org", path: "/")
            ])
            responseCache = FakeResponseCache(disk: 2_000_000, memory: 500_000)
            let counter = CleanupCounter()
            cleanupCounter = counter
            appState = AppState(
                domains: [Self.appDomain, Self.groupDomain],
                preferences: preferences,
                keychain: keychain,
                container: container,
                cookies: cookies,
                responseCache: responseCache,
                cleanup: AppStateReset.Cleanup("Close the orders database") { @MainActor in
                    counter.runs += 1
                    if let cleanupError { throw cleanupError }
                }
            )
        }

        /// Every file, folder and link under `root`, by its path from it, links not followed.
        func paths() -> Set<String> {
            let enumerator = FileManager.default.enumerator(atPath: resolvedRoot)
            var paths: Set<String> = []
            while let path = enumerator?.nextObject() as? String {
                paths.insert(path)
            }
            return paths
        }

        /// `entry`'s path from `root`.
        func relativePath(of entry: FileEntry) -> String {
            let path = entry.url.path(percentEncoded: false)
            return String(path.dropFirst(resolvedRoot.count).drop { $0 == "/" })
        }

        /// Deletes the temporary directory.
        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }
#endif
