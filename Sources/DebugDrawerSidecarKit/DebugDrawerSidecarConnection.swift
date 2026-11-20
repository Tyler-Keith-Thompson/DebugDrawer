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

        private let transport: DebugDrawerSidecarTransport
        private var channelForwarding: AnyCancellable?
        /// Waits for the sessions' first snapshot.
        private var connectingSessions: Task<Void, Never>?

        /// Connects to `app` over its socket and store, and, when its commands act only within a
        /// session, reads its sessions.
        ///
        /// - Parameter app: An app from a ``DebugDrawerSidecarAppList``.
        /// - Throws: What `DebugDrawerSidecarTransport(socketPath:storeDirectory:)` throws:
        ///   `DebugDrawerTransportError.accessDenied` when the system refuses the app group's
        ///   container, `unreachable` when the store can't be read.
        public init(app: DebugDrawerSidecarApp) throws(DebugDrawerTransportError) {
            self.app = app
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
        }

        /// Asks the app to open a session lasting `duration` seconds, or the app's maximum if
        /// that is shorter. Does nothing until ``sessions`` is read.
        ///
        /// - Parameters:
        ///   - duration: How long the session should last, in seconds.
        ///   - grant: The signed grant the company's server issued for this session, for an app
        ///     whose sessions require one (`DebugDrawerGrantPolicy`); `nil` otherwise.
        public func openSession(duration: TimeInterval, grant: String? = nil) {
            sessions?.send(.open(duration: duration, grant: grant))
        }

        /// Asks the app to end the open session, reverting its session-scoped changes. Does
        /// nothing until ``sessions`` is read.
        public func endSession() {
            sessions?.send(.end)
        }

        /// The plugin over a transport to the app's model of it, once the model's first snapshot
        /// arrives: the one made before, if the plugin was shown already.
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
            if let shown = hosted.first(where: { $0.id == plugin.id }) { return shown }
            let made = try await plugin.connect(transport)
            // Another call may have made it while this one waited: the first stays.
            if let shown = hosted.first(where: { $0.id == plugin.id }) { return shown }
            hosted.append(made)
            return made
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

        /// Throws `DebugDrawerTransportError.unreachable`.
        ///
        /// - Parameter app: Ignored.
        /// - Throws: `DebugDrawerTransportError.unreachable`, always.
        public init(app: DebugDrawerSidecarApp) throws(DebugDrawerTransportError) {
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

        /// Throws: release builds make no reports.
        ///
        /// - Parameters:
        ///   - redaction: Ignored.
        ///   - directory: Ignored.
        /// - Returns: Never.
        /// - Throws: `DebugDrawerReport.WriteFailed`, always.
        public func createReport(
            redaction: DebugDrawerRedaction = DebugDrawer.shared.redaction,
            in directory: URL = FileManager.default.temporaryDirectory
        ) throws(DebugDrawerReport.WriteFailed) -> URL {
            throw DebugDrawerReport.WriteFailed()
        }

        /// Does nothing.
        public func close() {}
    }
#endif
