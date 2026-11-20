import Combine
import DebugDrawer
import Foundation

// The apps in the group that serve a sidecar, read from the presence files they keep in the store
// (AppPresence, in DebugDrawerReceiver) and read again each time the presence directory's entries
// change: a dispatch source on the directory (DirectoryWatcher), so an app that starts serving
// shows up and one that stops drops off without anything polling. The files are written by rename,
// which is an entry change, so a rewrite (new capabilities, a newer last-seen time) is heard too.
// The directory is made if missing, since an app may start serving after the sidecar does and a
// directory that doesn't exist can't be watched.

#if DEBUG
    /// The apps in an app group that serve a sidecar, as they start and stop.
    ///
    /// ```swift
    /// let apps = DebugDrawerSidecarAppList(groupIdentifier: "TEAMID.com.example.debug")
    /// ```
    ///
    /// Each app that serves the group's store, a production app's `DebugDrawerReceiver` or a debug
    /// build's `DebugDrawerAppGroupStoreServer`, keeps a presence file there while it serves, and
    /// the list holds one ``DebugDrawerSidecarApp`` per file, sorted by name. An app that stops
    /// serving removes its file and leaves the list; one killed while serving stays, with the time
    /// it was last seen, until it serves again.
    ///
    /// Release builds get a stand-in whose list is always empty.
    @MainActor
    public final class DebugDrawerSidecarAppList: ObservableObject {
        /// The apps serving the store, sorted by display name, then bundle identifier.
        @Published public private(set) var apps: [DebugDrawerSidecarApp] = []
        /// Why the store can't be read, while it can't: `DebugDrawerTransportError.noAppGroupContainer`
        /// when the group resolves no container, `accessDenied` when the system refuses the
        /// store's directory, and `unreachable` when it can't be made or watched. The list is
        /// empty then.
        @Published public private(set) var error: DebugDrawerTransportError?

        /// The store's directory, whose apps the list holds; `nil` when the group resolves no
        /// container.
        public let storeDirectory: URL?
        private let watcher: DirectoryWatcher?

        /// The apps serving the store in `storeDirectory`.
        ///
        /// - Parameter storeDirectory: The store's directory, the one the apps'
        ///   `DebugDrawerReceiver` or `DebugDrawerAppGroupStoreServer` serves.
        public init(storeDirectory: URL) {
            self.storeDirectory = storeDirectory
            let changes: AsyncStream<Void>
            switch Self.watch(AppPresence.directory(inStore: storeDirectory)) {
            case let .success(watched):
                watcher = watched
                changes = watched.changes
            case let .failure(failure):
                watcher = nil
                error = failure
                return
            }
            read()
            Task { [weak self] in
                for await _ in changes {
                    self?.read()
                }
            }
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
            do {
                let group = try DebugDrawerAppGroupContainer(groupIdentifier: groupIdentifier, containerURL: containerURL)
                self.init(storeDirectory: group.storeDirectory)
            } catch {
                self.init(unavailable: error)
            }
        }

        private init(unavailable failure: DebugDrawerTransportError) {
            storeDirectory = nil
            watcher = nil
            error = failure
        }

        deinit {
            watcher?.cancel()
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

        /// Reads every presence file in the store again.
        private func read() {
            guard let storeDirectory else { return }
            let directory = AppPresence.directory(inStore: storeDirectory)
            let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
            let listed = names
                // A write in progress is a `.partial` file beside its file: skipped.
                .filter { $0.hasSuffix(".json") && !$0.hasPrefix(".") }
                .compactMap { name in
                    (try? Data(contentsOf: directory.appending(path: name, directoryHint: .notDirectory)))
                        .flatMap(AppPresence.decoded(from:))
                }
                .map { DebugDrawerSidecarApp($0, storeDirectory: storeDirectory) }
                .sorted { ($0.displayName, $0.bundleIdentifier) < ($1.displayName, $1.bundleIdentifier) }
            if listed != apps {
                apps = listed
            }
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
        /// The directory given, never read.
        public let storeDirectory: URL?

        /// A list that stays empty.
        ///
        /// - Parameter storeDirectory: Kept, and never read.
        public init(storeDirectory: URL) {
            self.storeDirectory = storeDirectory
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
            storeDirectory = nil
        }
    }
#endif
