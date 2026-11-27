import Combine
import DebugDrawer
import Foundation

// The sidecar's link to one app: a `DebugDrawerSidecarTransport` to the app's socket and store,
// the sessions' model when the app gates its commands, and the plugins the sidecar shows over it.
// The sessions' transport and each plugin's are made once their first snapshot arrives and then
// held for as long as the connection lives, so the sidecar keeps showing them, and the report has
// them, as the person moves between plugins. The transport switches between the socket and the
// store on its own; the connection only republishes which one is in use.
//
// Before the app launches (DD-296): a production app's receiver serves its capabilities only within
// a session and removes their snapshots as it stops, so the connection keeps each one it reads in
// the sidecar's own caches (SidecarSnapshotCache) and `prepare(_:)` makes the plugin from that copy
// at once. Its commands, and a session's open, wait in the store, where the receiver performs them
// in order as it starts: the open first, then the commands, in the session it opened. The open is
// "waiting for launch" until its file leaves the store, which the app does as it takes it, heard
// through the commands directory's dispatch source. Rejected: keeping capability snapshots in the
// shared store across stops (the receiver removes them so nothing an earlier launch wrote stays
// readable there), and `host(_:)` handing out the copy itself (its callers wait for the app's own
// snapshot, and would get an old one with no way to tell).
//
// The report is the drawer's: the hosted plugins' contributions (`DebugDrawerReportContributor`)
// in a folder each, zipped with a `summary.txt`, which names the app the sidecar reached rather
// than the sidecar itself, and the device both run on.

#if DEBUG
    /// A sidecar's connection to one app in its group: its sessions, and the plugins shown for it.
    ///
    /// ```swift
    /// let connection = try DebugDrawerSidecarConnection(app: app)
    /// connection.openSession(duration: 10 * 60)
    /// let console = try await connection.host(.console)
    /// ```
    ///
    /// It reaches the app over its socket while the app answers on it, and through its store while
    /// it doesn't (`DebugDrawerSidecarTransport`), switching on its own. ``DebugDrawerSidecarView``
    /// makes one for the app picked; use it directly to build a sidecar's screens yourself.
    ///
    /// Release builds get a stand-in whose initializer throws `DebugDrawerTransportError.unreachable`.
    @MainActor
    public final class DebugDrawerSidecarConnection: ObservableObject {
        /// The app connected to.
        public let app: DebugDrawerSidecarApp
        /// How the connection reaches the app now: its socket, or its store.
        @Published public private(set) var channel: DebugDrawerSidecarTransport.Channel
        /// The app's sessions, once their first snapshot arrives, when the app's commands act
        /// only within a session (``DebugDrawerSidecarApp/requiresSession``); `nil` before that,
        /// and for an app whose commands act at once.
        @Published public private(set) var sessions: DebugDrawerPluginTransport<DebugDrawerSessionState, DebugDrawerSessionCommand>?
        /// The plugins shown so far, in the order they were first shown, each over its transport
        /// to the app's model.
        @Published public private(set) var hosted: [AnyDebugDrawerPlugin] = []
        /// Whether a session's open ``openSession(duration:grant:)`` left in the app's store waits
        /// for the app to take it, as it launches or comes back to the foreground: `false` once the
        /// app takes it (``sessions`` then shows the session, or why there is none in the audit
        /// log), and for an open sent over the socket.
        @Published public private(set) var isWaitingForLaunch = false
        /// The ``DebugDrawerSidecarPlugin/id``s of the plugins ``prepare(_:)`` made from what the
        /// sidecar last read, whose model the app hasn't served since: each leaves as the app's own
        /// snapshot arrives.
        @Published public private(set) var preparedForLaunch: Set<String> = []

        private let transport: DebugDrawerSidecarTransport
        /// What the sidecar last read of each plugin, for ``prepare(_:)``.
        private let cache: SidecarSnapshotCache
        /// The file of the open waiting in the store, and a watcher of its directory, while
        /// ``isWaitingForLaunch``.
        private var queuedOpen: (file: URL, watcher: DirectoryWatcher)?
        /// The plugins shown so far, by the ``DebugDrawerSidecarPlugin/id`` they were asked for:
        /// the made plugin's own `id` may differ (a type's default is its type name), so it can't
        /// be what ``host(_:)`` finds them by.
        private var hostedByPluginID: [String: AnyDebugDrawerPlugin] = [:]
        private var channelForwarding: AnyCancellable?
        /// Waits for the sessions' first snapshot.
        private var connectingSessions: Task<Void, Never>?

        /// Connects to `app` over its socket and store, and, when its commands act only within a
        /// session, reads its sessions. What it reads of the plugins it shows is kept in the
        /// sidecar's caches, for ``prepare(_:)``.
        ///
        /// - Parameter app: An app from a ``DebugDrawerSidecarAppList``, or one addressed by
        ///   bundle ID that hasn't launched yet.
        /// - Throws: What `DebugDrawerSidecarTransport(socketPath:storeDirectory:)` throws:
        ///   `DebugDrawerTransportError.accessDenied` when the system refuses the app group's
        ///   container, `unreachable` when the store can't be read.
        public convenience init(app: DebugDrawerSidecarApp) throws(DebugDrawerTransportError) {
            try self.init(app: app, snapshotCacheDirectory: SidecarSnapshotCache.defaultDirectory)
        }

        /// Connects to `app` over its socket and store, and, when its commands act only within a
        /// session, reads its sessions, keeping what it reads of the plugins it shows in
        /// `snapshotCacheDirectory`, for ``prepare(_:)``.
        ///
        /// - Parameters:
        ///   - app: An app from a ``DebugDrawerSidecarAppList``, or one addressed by bundle ID that
        ///     hasn't launched yet.
        ///   - snapshotCacheDirectory: A directory of the sidecar's own, never the app group's
        ///     store, where the snapshots read are kept; made as one is kept. By default
        ///     `DebugDrawer Sidecar Snapshots` in the sidecar's caches directory.
        /// - Throws: What `DebugDrawerSidecarTransport(socketPath:storeDirectory:)` throws:
        ///   `DebugDrawerTransportError.accessDenied` when the system refuses the app group's
        ///   container, `unreachable` when the store can't be read.
        public init(app: DebugDrawerSidecarApp, snapshotCacheDirectory: URL) throws(DebugDrawerTransportError) {
            self.app = app
            cache = SidecarSnapshotCache(appDirectory: app.storeDirectory, bundleIdentifier: app.bundleIdentifier, in: snapshotCacheDirectory)
            transport = try DebugDrawerSidecarTransport(socketPath: app.socketPath, storeDirectory: app.storeDirectory)
            channel = transport.channel
            // The sidecar transport publishes on the main actor.
            channelForwarding = transport.$channel.dropFirst().sink { [weak self] channel in
                MainActor.assumeIsolated {
                    self?.channel = channel
                }
            }
            guard app.requiresSession else { return }
            connectingSessions = Task { [weak self, transport] in
                let sessions = try? await transport.connect(
                    toPlugin: DebugDrawerSessions.pluginID, snapshot: DebugDrawerSessionState.self, command: DebugDrawerSessionCommand.self
                )
                self?.sessions = sessions
            }
        }

        deinit {
            connectingSessions?.cancel()
            queuedOpen?.watcher.cancel()
        }

        /// Asks the app to open a session lasting `duration` seconds, or the app's maximum if
        /// that is shorter. Does nothing for an app whose commands act at once
        /// (``DebugDrawerSidecarApp/requiresSession`` is `false`).
        ///
        /// While the app isn't running, or is suspended, the open waits in its store, read or not
        /// read its sessions, and ``isWaitingForLaunch`` is `true` until the app takes it as it
        /// launches or comes back to the foreground. The session's length, and a grant's validity,
        /// count from then, not from now.
        ///
        /// - Parameters:
        ///   - duration: How long the session should last, in seconds.
        ///   - grant: The signed grant the company's server issued for this session, for an app
        ///     whose sessions require one (`DebugDrawerGrantPolicy`); `nil` otherwise.
        public func openSession(duration: TimeInterval, grant: String? = nil) {
            guard app.requiresSession else { return }
            let open = DebugDrawerSessionCommand.open(duration: duration, grant: grant)
            guard let file = transport.send(open, toPlugin: DebugDrawerSessions.pluginID) else { return }
            wait(forTheAppToTake: file)
        }

        /// Marks the open in `file` waiting for launch until the app takes it from the store.
        private func wait(forTheAppToTake file: URL) {
            queuedOpen?.watcher.cancel()
            queuedOpen = nil
            let commands = file.deletingLastPathComponent()
            guard let watcher = DirectoryWatcher(directory: commands) else { return }
            queuedOpen = (file, watcher)
            isWaitingForLaunch = true
            let changes = watcher.changes
            Task { [weak self] in
                for await _ in changes {
                    self?.noteQueuedOpenTaken()
                }
            }
            // The app may have taken it before the watcher started.
            noteQueuedOpenTaken()
        }

        /// Ends the wait once the queued open's file has left the store.
        private func noteQueuedOpenTaken() {
            guard let queuedOpen, !FileManager.default.fileExists(atPath: queuedOpen.file.path) else { return }
            queuedOpen.watcher.cancel()
            self.queuedOpen = nil
            isWaitingForLaunch = false
        }

        /// Asks the app to end the open session, reverting its session-scoped changes. Does
        /// nothing until ``sessions`` is read.
        public func endSession() {
            sessions?.send(.end)
        }

        /// The plugin over a transport to the app's model of it, once the model's first snapshot
        /// arrives: the one made before, if a plugin with the same ``DebugDrawerSidecarPlugin/id``
        /// was shown already, whatever the made plugin's own `id` is.
        ///
        /// It waits while the app doesn't serve the model, and throws `cancelled` if the task
        /// waiting is cancelled first.
        ///
        /// - Parameter plugin: The plugin to show.
        /// - Returns: The plugin, ready to draw.
        /// - Throws: `DebugDrawerTransportError.mismatchedTypes` when the app's model under the
        ///   plugin's ID has other types, `disconnected` once ``close()`` is called, and
        ///   `cancelled`.
        public func host(_ plugin: DebugDrawerSidecarPlugin) async throws(DebugDrawerTransportError) -> AnyDebugDrawerPlugin {
            if let shown = hostedByPluginID[plugin.id] { return shown }
            let made = try await plugin.connect(transport, plugin.preparesForLaunch ? cache : nil)
            // Another call may have made it while this one waited: the first stays.
            if let shown = hostedByPluginID[plugin.id] { return shown }
            hostedByPluginID[plugin.id] = made
            hosted.append(made)
            return made
        }

        /// The plugin over a transport that shows what the sidecar last read of the app's model,
        /// at once, for an app that isn't running: its commands wait in the app's store and are
        /// performed as it launches, after a session's open queued before them
        /// (``openSession(duration:grant:)``). It is the one shown already, if a plugin with the same
        /// ``DebugDrawerSidecarPlugin/id`` was, and ``host(_:)`` returns it from now on.
        ///
        /// Its ID is in ``preparedForLaunch`` until the app serves the model again; from then on
        /// it shows the app's own snapshots, as a hosted plugin does.
        ///
        /// - Parameter plugin: The plugin to prepare.
        /// - Returns: The plugin, ready to draw.
        /// - Throws: ``NeverRead`` when the sidecar never read the app's model of `plugin` (or no
        ///   longer can: the app's types changed), and for a plugin that shows what the app
        ///   collects while it runs (Console, Network, captures, events, payloads and reports), so
        ///   there is nothing to show before launch.
        public func prepare(_ plugin: DebugDrawerSidecarPlugin) throws(NeverRead) -> AnyDebugDrawerPlugin {
            if let shown = hostedByPluginID[plugin.id] { return shown }
            let id = plugin.id
            guard plugin.preparesForLaunch,
                  let made = plugin.prepare(transport, cache, { [weak self] in self?.preparedForLaunch.remove(id) })
            else { throw NeverRead() }
            hostedByPluginID[id] = made
            hosted.append(made)
            preparedForLaunch.insert(id)
            return made
        }

        /// Hosts each of `plugins` that is hosted as the app is reached (the app state) and that
        /// the app serves, so its report contribution is in every report, opened or not.
        func hostOnConnect(_ plugins: [DebugDrawerSidecarPlugin]) async {
            for plugin in plugins where plugin.hostsOnConnect && app.serves(plugin.id) {
                // A plugin that can't be reached is left out of the report; picking it shows why.
                _ = try? await host(plugin)
            }
        }

        /// Writes a bug report of the plugins shown so far that adopt
        /// `DebugDrawerReportContributor`, as the drawer's Create Report does, and zips it.
        ///
        /// The zip holds one folder, `<App>-Report-<ISO 8601 date with - for :>`, with a
        /// `summary.txt` naming the app connected to (its name, bundle ID, version and build) and
        /// the device, and a folder of files per contributing plugin, named after its title.
        ///
        /// - Parameters:
        ///   - redaction: The rules to mask what the files hold with; the sidecar's drawer's,
        ///     `DebugDrawer.shared.redaction`, by default.
        ///   - directory: Where the zip goes; created if missing. Defaults to the temporary
        ///     directory.
        /// - Returns: The zip's URL.
        /// - Throws: `DebugDrawerReport.WriteFailed` when a file can't be written or zipped.
        public func createReport(
            // The shared drawer's by default: a connection belongs to no drawer, and the sidecar's
            // own drawer, whose rules its person sets, is the shared one. A caller in a drawer of
            // its own passes that drawer's.
            redaction: DebugDrawerRedaction = DebugDrawer.shared.redaction,
            in directory: URL = FileManager.default.temporaryDirectory
        ) throws(DebugDrawerReport.WriteFailed) -> URL {
            let report = DebugDrawerReport(contributionsOf: hosted, redaction: redaction)
            let device = ReportSummary.current(at: Date())
            let summary = ReportSummary(
                appName: app.displayName,
                bundleID: app.bundleIdentifier,
                version: app.version.isEmpty ? "—" : app.version,
                build: app.build.isEmpty ? "—" : app.build,
                operatingSystem: device.operatingSystem,
                deviceModel: device.deviceModel,
                date: device.date
            )
            return try report.writeArchive(summary: summary, in: directory)
        }

        /// Disconnects from the app: the plugins shown keep their last snapshot and drop later
        /// commands.
        public func close() {
            connectingSessions?.cancel()
            queuedOpen?.watcher.cancel()
            queuedOpen = nil
            cache.stopFollowing()
            transport.close()
        }
    }
#else
    // The release stand-in: the same members, never connecting.

    /// Release builds connect to nothing: this stand-in's initializer throws
    /// `DebugDrawerTransportError.unreachable`.
    @MainActor
    public final class DebugDrawerSidecarConnection: ObservableObject {
        /// The app given.
        public let app: DebugDrawerSidecarApp
        /// Always `store`.
        @Published public private(set) var channel = DebugDrawerSidecarTransport.Channel.store
        /// Always `nil`.
        @Published public private(set) var sessions: DebugDrawerPluginTransport<DebugDrawerSessionState, DebugDrawerSessionCommand>?
        /// Always empty.
        @Published public private(set) var hosted: [AnyDebugDrawerPlugin] = []
        /// Always `false`.
        @Published public private(set) var isWaitingForLaunch = false
        /// Always empty.
        @Published public private(set) var preparedForLaunch: Set<String> = []

        /// Throws `DebugDrawerTransportError.unreachable`.
        ///
        /// - Parameter app: Ignored.
        /// - Throws: `DebugDrawerTransportError.unreachable`, always.
        public init(app: DebugDrawerSidecarApp) throws(DebugDrawerTransportError) {
            self.app = app
            throw .unreachable
        }

        /// Throws `DebugDrawerTransportError.unreachable`.
        ///
        /// - Parameters:
        ///   - app: Ignored.
        ///   - snapshotCacheDirectory: Ignored.
        /// - Throws: `DebugDrawerTransportError.unreachable`, always.
        public init(app: DebugDrawerSidecarApp, snapshotCacheDirectory: URL) throws(DebugDrawerTransportError) {
            self.app = app
            throw .unreachable
        }

        /// Does nothing.
        ///
        /// - Parameters:
        ///   - duration: Ignored.
        ///   - grant: Ignored.
        public func openSession(duration: TimeInterval, grant: String? = nil) {}

        /// Does nothing.
        public func endSession() {}

        /// Throws `DebugDrawerTransportError.unreachable`.
        ///
        /// - Parameter plugin: Ignored.
        /// - Returns: Never.
        /// - Throws: `DebugDrawerTransportError.unreachable`, always.
        public func host(_ plugin: DebugDrawerSidecarPlugin) async throws(DebugDrawerTransportError) -> AnyDebugDrawerPlugin {
            throw .unreachable
        }

        /// Throws ``NeverRead``: release builds read nothing.
        ///
        /// - Parameter plugin: Ignored.
        /// - Returns: Never.
        /// - Throws: ``NeverRead``, always.
        public func prepare(_ plugin: DebugDrawerSidecarPlugin) throws(NeverRead) -> AnyDebugDrawerPlugin {
            throw NeverRead()
        }

        /// Throws: release builds make no reports.
        ///
        /// - Parameters:
        ///   - redaction: Ignored.
        ///   - directory: Ignored.
        /// - Returns: Never.
        /// - Throws: `DebugDrawerReport.WriteFailed`, always.
        public func createReport(
            // The same default as the debug build's, so callers compile unchanged.
            redaction: DebugDrawerRedaction = DebugDrawer.shared.redaction,
            in directory: URL = FileManager.default.temporaryDirectory
        ) throws(DebugDrawerReport.WriteFailed) -> URL {
            throw DebugDrawerReport.WriteFailed()
        }

        /// Does nothing.
        public func close() {}
    }
#endif

extension DebugDrawerSidecarConnection {
    /// The sidecar never read the app's model of a plugin, so it has nothing to show or send before
    /// the app launches: the plugin shows once the app serves it, within a session for a
    /// production app's receiver.
    public struct NeverRead: Error, Equatable, Sendable, LocalizedError {
        /// The error.
        public init() {}

        /// Why the plugin can't be prepared.
        public var errorDescription: String? {
            "This plugin can't be prepared before the app launches: the sidecar hasn't read it from the app yet. It shows once the app serves it."
        }
    }
}
