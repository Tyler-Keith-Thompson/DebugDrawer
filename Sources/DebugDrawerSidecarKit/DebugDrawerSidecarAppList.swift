import Combine
import DebugDrawer
import Foundation

// The apps that serve a sidecar, read from the presence file each keeps in its own directory of
// its group's store (`<store>/apps/<bundle ID>/presence.json`, AppPresence in DebugDrawerReceiver)
// and read again each time one of those directories' entries changes: a dispatch source on each
// store's `apps/` directory, which hears an app's directory made or removed, and one on each app's
// directory, which hears its presence file written or removed (DirectoryWatcher), so an app that
// starts serving shows up and one that stops drops off without anything polling. The files are
// written by rename, which is an entry change, so a rewrite (new capabilities, a newer last-seen
// time) is heard too. The `apps/` directory is made if missing, since an app may start serving
// after the sidecar does and a directory that doesn't exist can't be watched.
//
// A list may read several groups' stores: the OS lets every app of a group read the whole
// container, so a company that keeps its apps apart gives each its own group, and the sidecar
// joins each. An app found in two groups is listed once, from the presence written last. A
// presence file whose bundle ID doesn't name the directory it is in is skipped: an app writes its
// own directory only.

#if DEBUG
    /// The apps in one or more app groups that serve a sidecar, as they start and stop.
    ///
    /// ```swift
    /// let apps = DebugDrawerSidecarAppList(groupIdentifier: "TEAMID.com.example.debug")
    /// ```
    ///
    /// Each app that serves a group's store, a production app's `DebugDrawerReceiver` or a debug
    /// build's `DebugDrawerAppGroupStoreServer`, keeps a presence file in its own directory of
    /// the store while it serves, and the list holds one ``DebugDrawerSidecarApp`` per app, sorted
    /// by name. An app that stops serving removes its file and leaves the list; one killed while
    /// serving stays, with the time it was last seen, until it serves again.
    ///
    /// Apps of one group can read each other's files: the system doesn't keep them apart within a
    /// group. To keep them apart, give each app a group of its own and list them all with
    /// ``init(groupIdentifiers:containerURL:)``, the sidecar joining every group.
    ///
    /// Release builds get a stand-in whose list is always empty.
    @MainActor
    public final class DebugDrawerSidecarAppList: ObservableObject {
        /// The apps serving the stores, sorted by display name, then bundle identifier.
        @Published public private(set) var apps: [DebugDrawerSidecarApp] = []
        /// Why a store can't be read, while one can't: `DebugDrawerTransportError.noAppGroupContainer`
        /// when a group resolves no container, `accessDenied` when the system refuses a store's
        /// directory, and `unreachable` when it can't be made or watched; the first group's that
        /// fails, in the order given. The apps of the other stores are still listed.
        @Published public private(set) var error: DebugDrawerTransportError?

        /// The groups' stores whose apps the list holds, in the order given; a group that
        /// resolves no container has none.
        public let storeDirectories: [URL]
        /// A watcher of each store's `apps/` directory, by store.
        private var storeWatchers: [URL: DirectoryWatcher] = [:]
        /// A watcher of each app's directory, by directory.
        private var appWatchers: [URL: DirectoryWatcher] = [:]

        /// The apps serving the group's store in `storeDirectory`.
        ///
        /// - Parameter storeDirectory: The group's store, the one the apps'
        ///   `DebugDrawerReceiver` or `DebugDrawerAppGroupStoreServer` is handed
        ///   (`DebugDrawerAppGroupContainer.storeDirectory`).
        public convenience init(storeDirectory: URL) {
            self.init(storeDirectories: [storeDirectory])
        }

        /// The apps serving any of the groups' stores in `storeDirectories`, merged.
        ///
        /// - Parameter storeDirectories: The groups' stores.
        public convenience init(storeDirectories: [URL]) {
            self.init(storeDirectories: storeDirectories, failure: nil)
        }

        /// The apps serving the store in the app group's container, in its `DebugDrawer` directory
        /// (`DebugDrawerAppGroupContainer.storeDirectory`).
        ///
        /// - Parameters:
        ///   - groupIdentifier: The app group the sidecar and the apps list in their
        ///     `com.apple.security.application-groups` entitlement.
        ///   - containerURL: Resolves a group's container; the system's by default.
        public convenience init(
            groupIdentifier: String,
            containerURL: (String) -> URL? = { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
        ) {
            self.init(groupIdentifiers: [groupIdentifier], containerURL: containerURL)
        }

        /// The apps serving the stores of several app groups, merged: for a company that gives
        /// each app a group of its own, which the sidecar joins too.
        ///
        /// - Parameters:
        ///   - groupIdentifiers: The app groups, each listed in the sidecar's
        ///     `com.apple.security.application-groups` entitlement and in its apps'.
        ///   - containerURL: Resolves a group's container; the system's by default.
        public convenience init(
            groupIdentifiers: [String],
            containerURL: (String) -> URL? = { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
        ) {
            var stores: [URL] = []
            var failure: DebugDrawerTransportError?
            for groupIdentifier in groupIdentifiers {
                do {
                    stores.append(try DebugDrawerAppGroupContainer(groupIdentifier: groupIdentifier, containerURL: containerURL).storeDirectory)
                } catch {
                    failure = failure ?? error
                }
            }
            self.init(storeDirectories: stores, failure: failure)
        }

        private init(storeDirectories: [URL], failure: DebugDrawerTransportError?) {
            self.storeDirectories = storeDirectories
            error = failure
            for store in storeDirectories {
                switch Self.watch(AppGroupStoreLayout.appsDirectory(inStore: store)) {
                case let .success(watcher):
                    storeWatchers[store] = watcher
                    follow(watcher)
                case let .failure(failure):
                    error = error ?? failure
                }
            }
            refresh()
        }

        /// A watcher of `directory`, made first if missing: an app may start serving after the
        /// sidecar starts listing.
        private static func watch(_ directory: URL) -> Result<DirectoryWatcher, DebugDrawerTransportError> {
            do throws(DebugDrawerTransportError) {
                try DirectoryAccess.prepare(directory, need: .read, otherwise: .unreachable)
            } catch {
                return .failure(error)
            }
            return DirectoryWatcher(directory: directory).map { .success($0) } ?? .failure(.unreachable)
        }

        /// Refreshes the list each time `watcher` hears a change, until it is cancelled or let go.
        private func follow(_ watcher: DirectoryWatcher) {
            let changes = watcher.changes
            Task { [weak self] in
                for await _ in changes {
                    self?.refresh()
                }
            }
        }

        /// Watches each app directory the stores now hold, lets go of those gone, and reads every
        /// presence file again.
        private func refresh() {
            let directories = Set(storeWatchers.keys.flatMap(Self.appDirectories(inStore:)))
            for gone in appWatchers.keys where !directories.contains(gone) {
                appWatchers.removeValue(forKey: gone)?.cancel()
            }
            for directory in directories where appWatchers[directory] == nil {
                guard let watcher = DirectoryWatcher(directory: directory) else { continue }
                appWatchers[directory] = watcher
                follow(watcher)
            }
            let listed = Dictionary(
                directories.compactMap(Self.app(in:)).map { ($0.bundleIdentifier, $0) },
                uniquingKeysWith: { $0.lastSeen >= $1.lastSeen ? $0 : $1 }
            )
            .values
            .sorted { ($0.displayName, $0.bundleIdentifier) < ($1.displayName, $1.bundleIdentifier) }
            if listed != apps {
                apps = listed
            }
        }

        /// The app directories in the store in `store`.
        private static func appDirectories(inStore store: URL) -> [URL] {
            let apps = AppGroupStoreLayout.appsDirectory(inStore: store)
            let names = (try? FileManager.default.contentsOfDirectory(atPath: apps.path)) ?? []
            return names
                .filter { !$0.hasPrefix(".") }
                .map { apps.appending(path: $0, directoryHint: .isDirectory) }
        }

        /// The app whose presence file is in `directory`, if it has one that names that
        /// directory; a write in progress is a `.partial` file beside it, never read.
        private static func app(in directory: URL) -> DebugDrawerSidecarApp? {
            guard let data = try? Data(contentsOf: AppPresence.file(inAppDirectory: directory)),
                  let presence = AppPresence.decoded(from: data),
                  AppGroupStoreLayout.fileName(presence.identity.bundleIdentifier) == directory.lastPathComponent
            else { return nil }
            return DebugDrawerSidecarApp(presence, storeDirectory: directory)
        }
    }
#else
    // The release stand-in: the same members, listing nothing.

    /// Release builds list no app: this stand-in's list is always empty.
    @MainActor
    public final class DebugDrawerSidecarAppList: ObservableObject {
        /// Always empty.
        @Published public private(set) var apps: [DebugDrawerSidecarApp] = []
        /// Always `DebugDrawerTransportError.unreachable`.
        @Published public private(set) var error: DebugDrawerTransportError? = .unreachable
        /// The directories given, never read.
        public let storeDirectories: [URL]

        /// A list that stays empty.
        ///
        /// - Parameter storeDirectory: Kept, and never read.
        public init(storeDirectory: URL) {
            storeDirectories = [storeDirectory]
        }

        /// A list that stays empty.
        ///
        /// - Parameter storeDirectories: Kept, and never read.
        public init(storeDirectories: [URL]) {
            self.storeDirectories = storeDirectories
        }

        /// A list that stays empty.
        ///
        /// - Parameters:
        ///   - groupIdentifier: Ignored.
        ///   - containerURL: Never called.
        public init(
            groupIdentifier: String,
            containerURL: (String) -> URL? = { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
        ) {
            storeDirectories = []
        }

        /// A list that stays empty.
        ///
        /// - Parameters:
        ///   - groupIdentifiers: Ignored.
        ///   - containerURL: Never called.
        public init(
            groupIdentifiers: [String],
            containerURL: (String) -> URL? = { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
        ) {
            storeDirectories = []
        }
    }
#endif
