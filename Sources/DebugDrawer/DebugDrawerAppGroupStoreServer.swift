import Foundation
import os

// The app's end of the app-group store: it writes every registered model's snapshot to the store
// as it changes, through one `RegistrySession` that wants every plugin, and performs the commands
// viewers leave there. Commands left while the app was suspended or not running are performed when
// it starts serving, then each as its file lands. Writes run on the main actor, where the models
// are: a snapshot is written once per change the transport folds, not once per edit.

#if DEBUG
    /// Keeps a ``DebugDrawerModelRegistry``'s snapshots in a directory both apps of an app group
    /// can reach, and performs the commands a ``DebugDrawerAppGroupStoreTransport`` leaves there.
    ///
    /// The snapshots stay when the app is suspended or quits, so a viewer reads the last state
    /// then, and its commands wait for the app to serve again.
    ///
    /// ```swift
    /// let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.example.debug")!
    /// let server = DebugDrawerAppGroupStoreServer(registry: registry, directory: container.appending(path: "DebugDrawer"))
    /// try server.start()
    /// ```
    ///
    /// Release builds get a stand-in that writes nothing.
    @MainActor
    public final class DebugDrawerAppGroupStoreServer {
        private static let logger = Logger(subsystem: "DebugDrawer", category: "DebugDrawerAppGroupStoreServer")

        private let registry: DebugDrawerModelRegistry
        private let layout: AppGroupStoreLayout
        /// The store's directory.
        public let directory: URL
        private var session: RegistrySession?
        private var watcher: DirectoryWatcher?
        private var performing: Task<Void, Never>?

        /// A server of `registry`'s models into `directory`; it writes once started.
        ///
        /// - Parameters:
        ///   - registry: The models to serve.
        ///   - directory: The store's directory, usually in the app group's container. It is made
        ///     if it doesn't exist.
        public init(registry: DebugDrawerModelRegistry, directory: URL) {
            self.registry = registry
            self.directory = directory
            layout = AppGroupStoreLayout(directory: directory)
        }

        /// Whether the server is writing snapshots and performing commands.
        public var isRunning: Bool {
            session != nil
        }

        /// Writes every registered model's snapshot, performs the commands waiting in the store,
        /// and goes on doing both as they change. Does nothing while the server runs.
        ///
        /// - Throws: ``DebugDrawerTransportError/cannotServe`` when the store's directories can't
        ///   be made or watched.
        public func start() throws(DebugDrawerTransportError) {
            guard session == nil else { return }
            guard layout.create(), let watcher = DirectoryWatcher(directory: layout.commands) else { throw .cannotServe }
            let layout = layout
            let session = RegistrySession(registry: registry, link: .store) { message in
                Self.write(StoreDocument(message), to: layout.snapshotFile(for: message.pluginID))
            }
            self.session = session
            self.watcher = watcher
            session.forwardEveryPlugin()
            performing = Task { [weak self] in
                self?.performWaitingCommands()
                for await _ in watcher.changes {
                    self?.performWaitingCommands()
                }
            }
        }

        /// Stops writing snapshots and performing commands. The snapshots written stay in the store.
        public func stop() {
            session?.close()
            session = nil
            watcher?.cancel()
            watcher = nil
            performing?.cancel()
            performing = nil
        }

        /// Performs each command file in the store, oldest first, removing it first so it runs
        /// once.
        private func performWaitingCommands() {
            guard let session else { return }
            for file in layout.messageFiles(in: layout.commands) {
                let data = try? Data(contentsOf: file)
                do {
                    try FileManager.default.removeItem(at: file)
                } catch {
                    Self.logger.error("Couldn't remove a command file, so it wasn't performed: \(error.localizedDescription, privacy: .public)")
                    continue
                }
                guard let data, let document = StoreDocument.decoded(from: data) else {
                    Self.logger.notice("Dropped a command file this build can't read")
                    continue
                }
                guard document.isReadable else {
                    let version = document.writer.version
                    Self.logger.notice("Dropped a command file from protocol version \(version, privacy: .public), which this build doesn't speak")
                    continue
                }
                // The writer's hello first, so the session knows what that viewer has; then the
                // message, which the session acts on if it is a command and drops otherwise.
                session.receive(.hello(document.writer))
                session.receive(document.message)
            }
        }

        private static func write(_ document: StoreDocument, to file: URL) {
            do {
                try document.encoded().write(to: file, options: .atomic)
            } catch {
                let pluginID = document.message.pluginID
                logger.error("Couldn't write \(pluginID, privacy: .public)'s snapshot: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
#else
    // The release stand-in: the same members, writing nothing.

    /// Release builds serve nothing: this stand-in writes nothing.
    @MainActor
    public final class DebugDrawerAppGroupStoreServer {
        /// The store's directory, never written.
        public let directory: URL

        /// A server that never writes.
        ///
        /// - Parameters:
        ///   - registry: Ignored.
        ///   - directory: Kept, and never written.
        public init(registry: DebugDrawerModelRegistry, directory: URL) {
            self.directory = directory
        }

        /// Always `false`.
        public var isRunning: Bool {
            false
        }

        /// Does nothing.
        public func start() throws(DebugDrawerTransportError) {}

        /// Does nothing.
        public func stop() {}
    }
#endif
