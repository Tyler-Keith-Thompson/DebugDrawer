import DebugDrawerReceiver
import Foundation
import os

// The app's end of the app-group store: it writes every registered model's snapshot to the store
// as it changes, through one `RegistrySession` that wants every plugin, and performs the commands
// viewers leave there. Commands left while the app was not running are performed when it starts
// serving, those left while it was suspended as it comes back to the foreground, then each as its
// file lands. Writes run on the main actor, where the models are: a snapshot is written once per
// change the transport folds, not once per edit.
//
// The directory's dispatch source is the wake-up while the app runs. Nothing promises what a
// suspended app hears of it, so coming to the foreground performs what waits too, synchronously in
// the system's notification. Both may find the same file; it runs once, as each is removed before
// it is performed. Rejected: a Darwin notification posted by the viewer (a suspended app doesn't
// run to hear it either, and the directory's own event already wakes a running one) and
// NSFileCoordinator (see DirectoryWatcher). Starting removes the snapshot files an earlier
// run's cut-off writes left (AppGroupStoreLayout), as this server is the only snapshot writer.

#if DEBUG
    #if os(macOS)
        import AppKit
    #elseif os(watchOS)
        import WatchKit
    #elseif canImport(UIKit)
        import UIKit
    #endif

    /// Keeps a ``DebugDrawerModelRegistry``'s snapshots in a directory both apps of an app group
    /// can reach, and performs the commands a ``DebugDrawerAppGroupStoreTransport`` leaves there.
    ///
    /// The snapshots stay when the app is suspended or quits, so a viewer reads the last state
    /// then, and its commands wait for the app to serve again: the server performs them as it
    /// starts, as the app comes back to the foreground, and as each lands while it runs.
    ///
    /// ```swift
    /// let group = try DebugDrawerAppGroupContainer(groupIdentifier: "TEAMID.com.example.debug")
    /// let server = DebugDrawerAppGroupStoreServer(registry: registry, directory: group.storeDirectory)
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
        private var foregroundObservation: (any NSObjectProtocol)?

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
        /// and goes on doing both as they change, and as the app comes back to the foreground.
        /// Does nothing while the server runs.
        ///
        /// - Throws: ``DebugDrawerTransportError/accessDenied`` when the system refuses access to
        ///   the store's directories (the app group missing from the app's entitlements, or the
        ///   person declining macOS's prompt), and ``DebugDrawerTransportError/cannotServe`` when
        ///   they can't be made or watched for another reason. Nothing is written then.
        public func start() throws(DebugDrawerTransportError) {
            guard session == nil else { return }
            try layout.create(otherwise: .cannotServe)
            guard let watcher = DirectoryWatcher(directory: layout.commands) else { throw .cannotServe }
            layout.removeCutOffSnapshots()
            let layout = layout
            let session = RegistrySession(registry: registry, link: .store) { message in
                Self.write(StoreDocument(message), to: layout.snapshotFile(for: message.pluginID), in: layout)
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
            // No queue, so the commands are performed before the post returns, not on a later
            // turn of the main run loop. The system posts it on the main thread.
            foregroundObservation = NotificationCenter.default.addObserver(forName: Self.foreground, object: nil, queue: nil) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.performWaitingCommands()
                }
            }
        }

        /// Stops writing snapshots and performing commands. The snapshots written stay in the store.
        public func stop() {
            if let foregroundObservation {
                NotificationCenter.default.removeObserver(foregroundObservation)
            }
            foregroundObservation = nil
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

        /// What the system posts as the app comes to the foreground: on the Mac, where apps aren't
        /// suspended, as it becomes active.
        private static var foreground: Notification.Name {
            #if os(macOS)
                NSApplication.willBecomeActiveNotification
            #elseif os(watchOS)
                WKApplication.willEnterForegroundNotification
            #else
                // Mac Catalyst takes this branch too: a Catalyst app is a UIKit app, and UIKit
                // posts it there.
                UIApplication.willEnterForegroundNotification
            #endif
        }

        private static func write(_ document: StoreDocument, to file: URL, in layout: AppGroupStoreLayout) {
            do {
                try layout.write(document.encoded(), to: file)
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
