import Foundation
import os

// The viewer's end of the app-group store: it reads every snapshot file when made and again each
// time the snapshots directory changes, handing the ones that changed to `RemoteModels`, and
// leaves each command as a file of its own for the app to perform. Command files are named by the
// wall clock in nanoseconds, then a count, then a UUID, so the app performs one viewer's commands
// in the order sent, and two viewers' never collide. A file a build this one shares no protocol
// version with wrote is skipped rather than closing the store, as a stale file can outlive the app
// that wrote it.

#if DEBUG
    /// A ``DebugDrawerTransport`` to the snapshots an app's ``DebugDrawerAppGroupStoreServer``
    /// keeps in a shared directory: readable while the app is suspended or not running.
    ///
    /// A transport it hands out shows the snapshot the store holds, then each one the app writes.
    /// A command waits in the store until the app serves it, then lands in a later snapshot.
    ///
    /// Release builds get a stand-in whose initializer throws
    /// ``DebugDrawerTransportError/unreachable``.
    @MainActor
    public final class DebugDrawerAppGroupStoreTransport: DebugDrawerTransport {
        private static let logger = Logger(subsystem: "DebugDrawer", category: "DebugDrawerAppGroupStoreTransport")

        private let layout: AppGroupStoreLayout
        private let watcher: DirectoryWatcher
        private let models: RemoteModels
        /// What each snapshot file held when last read, so only a changed one is decoded.
        private var read: [URL: Data] = [:]

        /// Reads the store in `directory`, making it if it doesn't exist, so the app's first
        /// snapshots are seen as they land.
        ///
        /// - Parameter directory: The store's directory, the app's
        ///   ``DebugDrawerAppGroupStoreServer/directory``.
        /// - Throws: ``DebugDrawerTransportError/unreachable`` when the directory can't be made or
        ///   watched.
        public init(directory: URL) throws(DebugDrawerTransportError) {
            let layout = AppGroupStoreLayout(directory: directory)
            guard layout.create(), let watcher = DirectoryWatcher(directory: layout.snapshots) else { throw .unreachable }
            self.layout = layout
            self.watcher = watcher
            var sequence = 0
            models = RemoteModels(link: .store) { message in
                sequence += 1
                Self.leave(StoreDocument(message), in: layout, sequence: sequence)
            }
            readSnapshots()
            Task { [weak self] in
                for await _ in watcher.changes {
                    self?.readSnapshots()
                }
            }
        }

        deinit {
            watcher.cancel()
        }

        /// The plugin's model, from the snapshot the store holds, or the first the app writes.
        ///
        /// - Parameters:
        ///   - pluginID: The ID the model was registered under.
        ///   - snapshot: The model's `Snapshot` type.
        ///   - command: The model's `Command` type.
        /// - Returns: A transport showing the model's snapshots as the app writes them and leaving
        ///   its commands for the app.
        /// - Throws: ``DebugDrawerTransportError/mismatchedTypes`` or
        ///   ``DebugDrawerTransportError/cancelled``.
        public func connect<Snapshot: Codable & Equatable & Sendable, Command: Codable & Sendable>(
            toPlugin pluginID: String,
            snapshot: Snapshot.Type,
            command: Command.Type
        ) async throws(DebugDrawerTransportError) -> DebugDrawerPluginTransport<Snapshot, Command> {
            try await models.connect(toPlugin: pluginID, snapshot: snapshot, command: command, holding: self)
        }

        /// Reads each snapshot file that changed since it was last read.
        private func readSnapshots() {
            for file in layout.messageFiles(in: layout.snapshots) {
                guard let data = try? Data(contentsOf: file), read[file] != data else { continue }
                read[file] = data
                guard let document = StoreDocument.decoded(from: data) else { continue }
                guard document.isReadable else {
                    let version = document.writer.version
                    Self.logger.notice("Skipped a snapshot file from protocol version \(version, privacy: .public), which this build doesn't speak")
                    continue
                }
                // The writer's hello first, so a command goes only to an app that takes them.
                models.receive(.hello(document.writer))
                models.receive(document.message)
            }
        }

        private static func leave(_ document: StoreDocument, in layout: AppGroupStoreLayout, sequence: Int) {
            let time = String(format: "%020llu", clock_gettime_nsec_np(CLOCK_REALTIME))
            let count = String(format: "%010ld", sequence)
            let file = layout.commands.appending(path: "\(time)-\(count)-\(UUID().uuidString).json", directoryHint: .notDirectory)
            do {
                try document.encoded().write(to: file, options: .atomic)
            } catch {
                let pluginID = document.message.pluginID
                logger.error("Couldn't leave a command for \(pluginID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }
#else
    // The release stand-in: the same members, never reading.

    /// Release builds read nothing: this stand-in's initializer throws
    /// ``DebugDrawerTransportError/unreachable``.
    @MainActor
    public final class DebugDrawerAppGroupStoreTransport: DebugDrawerTransport {
        /// Throws ``DebugDrawerTransportError/unreachable``.
        ///
        /// - Parameter directory: Ignored.
        /// - Throws: ``DebugDrawerTransportError/unreachable``, always.
        public init(directory: URL) throws(DebugDrawerTransportError) {
            throw .unreachable
        }

        /// Throws ``DebugDrawerTransportError/unreachable``.
        ///
        /// - Parameters:
        ///   - pluginID: Ignored.
        ///   - snapshot: Ignored.
        ///   - command: Ignored.
        /// - Returns: Never.
        /// - Throws: ``DebugDrawerTransportError/unreachable``, always.
        public func connect<Snapshot: Codable & Equatable & Sendable, Command: Codable & Sendable>(
            toPlugin pluginID: String,
            snapshot: Snapshot.Type,
            command: Command.Type
        ) async throws(DebugDrawerTransportError) -> DebugDrawerPluginTransport<Snapshot, Command> {
            throw .unreachable
        }
    }
#endif
