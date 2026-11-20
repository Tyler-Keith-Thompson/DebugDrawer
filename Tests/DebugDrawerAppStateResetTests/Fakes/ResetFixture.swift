#if DEBUG
    import Foundation
    @testable import DebugDrawerAppStateReset

    /// An app's state for a sidecar to reset, as fixture data: a container laid out in a new
    /// temporary directory, with DebugDrawer's own files beside the app's, and fakes for the other
    /// seams, each holding something of every kind, DebugDrawer's own keys among the defaults.
    ///
    /// ```
    /// Documents/notes.txt, Documents/DebugDrawer Export.txt
    /// Application Support/store.sqlite
    /// Caches/thumbs/1.png, Caches/DebugDrawer/Recordings/a.mov
    /// ```
    @MainActor
    struct ResetFixture {
        /// The temporary directory that holds the container.
        let root: URL
        let preferences: FakePreferenceStore
        let keychain: FakeKeychain
        let cookies: FakeCookieStore
        let responseCache: FakeResponseCache
        let appState: AppState

        static let appDomain = "com.example.app"

        /// Lays the container out.
        ///
        /// - Parameter cleanup: The app's cleanup; `nil` for none.
        init(cleanup: AppStateReset.Cleanup? = nil) throws {
            root = FileManager.default.temporaryDirectory.appending(path: "AppStateResetRequests-\(UUID().uuidString)", directoryHint: .isDirectory)
            let files: [String: String] = [
                "Documents/notes.txt": "notes",
                "Documents/DebugDrawer Export.txt": "export",
                "Application Support/store.sqlite": "0123456789",
                "Caches/thumbs/1.png": "png",
                "Caches/DebugDrawer/Recordings/a.mov": "movie"
            ]
            for (path, contents) in files {
                let url = root.appending(path: path)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(contents.utf8).write(to: url)
            }
            let container = AppContainer(
                files: [
                    FileArea(name: "Documents", directory: root.appending(path: "Documents")),
                    FileArea(name: "Application Support", directory: root.appending(path: "Application Support"))
                ],
                caches: [FileArea(name: "Caches", directory: root.appending(path: "Caches"))],
                kept: [],
                appFolderName: Self.appDomain
            )
            preferences = FakePreferenceStore([
                Self.appDomain: ["onboarded", "counter", "com.debugdrawer.tweaks.greeting", "DebugDrawer.LogLevels.raisedSubsystems"]
            ])
            keychain = FakeKeychain([
                FakeKeychain.password(service: "api.example.com", account: "alice@example.com"),
                KeychainItem(itemClass: .key, service: nil, account: nil, label: "Signing key", persistentReference: Data("key".utf8))
            ])
            cookies = FakeCookieStore([
                StoredCookie(store: .http, name: "session", domain: "example.com", path: "/"),
                StoredCookie(store: .http, name: "theme", domain: "example.com", path: "/"),
                StoredCookie(store: .web, name: "tracking", domain: "other.org", path: "/")
            ])
            responseCache = FakeResponseCache(disk: 2_000_000, memory: 500_000)
            var appState = AppState(
                domains: [Self.appDomain],
                preferences: preferences,
                keychain: keychain,
                container: container,
                cookies: cookies,
                responseCache: responseCache,
                cleanup: cleanup
            )
            appState.namesKeychainAccounts = false
            self.appState = appState
        }

        /// Whether the file at `path`, from `root`, is there.
        func exists(_ path: String) -> Bool {
            FileManager.default.fileExists(atPath: root.appending(path: path).path(percentEncoded: false))
        }

        /// Deletes the temporary directory.
        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }
#endif
