#if canImport(DebugDrawerRemote)
    import Combine
    import DebugDrawer
    import DebugDrawerRemote
    import Foundation
    import os

    // The device-lab bridge (DD-107): a QA lab drives production builds on many devices from one
    // Mac. Each device's sidecar relays what it reaches of the app picked to a Mac viewer over the
    // network transport, so the production app's receiver still only ever talks over the app
    // group, and opens no listener of its own.
    //
    // The relay is a model registry of its own, served by a `DebugDrawerNetworkServer`, so a viewer
    // pairs with a code the sidecar shows and then reads it as it would a debug build's drawer. It
    // relays only while the server listens and a session the sidecar's person opened is open in
    // the app, and only the capabilities that session may read (`DebugDrawerSession.allows`, the
    // receiver's own rule for what it writes); everything else waits for a snapshot the receiver
    // never writes. For each, it connects through a sidecar transport made for that session, and
    // registers the plugin once the app's first snapshot arrives. As the session ends, expires (at
    // its expiry date, on a timer of its own, so an app suspended past the expiry doesn't keep
    // being relayed from what the store last held), or the server stops, every plugin is
    // unregistered and the transport closed, so nothing is served past the session, and the next
    // session starts from a new transport, which holds no snapshot of the last one. A viewer's
    // command goes back through the transport to the receiver, which applies or refuses it as it
    // would the sidecar's own: the relay adds no gate and widens none. The sessions themselves are
    // not relayed: a viewer can't open, end or read a session's grant, only the relay's own snapshot
    // (the app, until when, and the IDs relayed).
    //
    // Rejected: the relay in the production app (a listener in the build that ships, outside the
    // app group's trust boundary); a module of its own (it would depend on the kit, which no module
    // does, for a feature of the sidecar app); `DebugDrawerRemote` holding it (it would depend on the
    // kit); relaying each plugin only as a viewer subscribes (the registry serves registered models
    // only, so it would take a new hook in core, and each relayed plugin costs a file read per
    // change); relaying the sessions too (a viewer could end the session the sidecar's person holds,
    // or open one with a grant meant for the device).

    #if DEBUG
        /// Relays an app's capabilities, read through the sidecar within the session its person
        /// opens, to a viewer on a Mac over the local network, and the viewer's commands back.
        ///
        /// ```swift
        /// let relay = DebugDrawerSidecarRelay(connection: connection)
        /// try await relay.start()
        /// ```
        ///
        /// Nothing listens until ``start()``, and nothing is relayed until a session is open in
        /// the app: then each capability the session may read is served under its own ID, for as
        /// long as the session lasts. A viewer pairs with the code the sidecar shows
        /// (``server``'s `pairingRequests`), reads ``Snapshot`` under ``pluginID``, and connects to
        /// the IDs it lists. Its commands reach the app as the sidecar's own would, applied or
        /// refused by the app within the session and its grant. ``DebugDrawerSidecarView`` shows
        /// one for the app picked when it carries `debugDrawerSidecarRelay(_:startsServing:)`.
        ///
        /// Release builds get a stand-in that never listens.
        @MainActor
        public final class DebugDrawerSidecarRelay: ObservableObject {
            private static let logger = Logger(subsystem: "DebugDrawerSidecarKit", category: "DebugDrawerSidecarRelay")
            /// The ID a viewer reads the relay's ``Snapshot`` under.
            public nonisolated static let pluginID = "DebugDrawer.SidecarRelay"

            /// The connection to the app relayed.
            public let connection: DebugDrawerSidecarConnection
            /// What a viewer pairs with and connects to: its `pairingRequests` hold the codes to
            /// show.
            public let server: DebugDrawerNetworkServer
            /// What a viewer reads of the relay now.
            @Published public private(set) var snapshot: Snapshot

            private let registry: DebugDrawerModelRegistry
            private let status: RelayStatus
            private let timer: any SessionTimer
            /// The app's sessions, as last read; `nil` until read.
            private var sessionState: DebugDrawerSessionState?
            /// The session whose expiry date passed, which is relayed no more even before the app
            /// says it ended.
            private var expiredSessionID: UUID?
            /// Whether the server listens.
            private var isServing = false
            /// What is relayed for the open session; `nil` outside one.
            private var relaying: SessionRelay?
            private var subscriptions: Set<AnyCancellable> = []
            private var following: Task<Void, Never>?

            /// A relay of the app `connection` reaches, listening once started.
            ///
            /// - Parameters:
            ///   - connection: The sidecar's connection to the app, whose sessions the relay
            ///     follows.
            ///   - configuration: Where to listen, and whether to advertise over Bonjour.
            public convenience init(connection: DebugDrawerSidecarConnection, configuration: DebugDrawerNetworkServerConfiguration = .init()) {
                self.init(connection: connection, timer: RunLoopSessionTimer()) { registry in
                    DebugDrawerNetworkServer(registry: registry, configuration: configuration)
                }
            }

            /// A relay with the session timer and server given.
            package init(
                connection: DebugDrawerSidecarConnection,
                timer: any SessionTimer,
                server makeServer: (DebugDrawerModelRegistry) -> DebugDrawerNetworkServer
            ) {
                self.connection = connection
                self.timer = timer
                registry = DebugDrawerModelRegistry()
                server = makeServer(registry)
                let idle = Snapshot(app: connection.app)
                snapshot = idle
                status = RelayStatus(snapshot: idle)
                registry.register(status, id: Self.pluginID)
                // `$port` publishes before the change lands, so the value is read from what it
                // sends.
                server.$port.sink { [weak self] port in
                    self?.isServing = port != nil
                    self?.update()
                }
                .store(in: &subscriptions)
                connection.$sessions.compactMap { $0 }.first().sink { [weak self] sessions in
                    self?.follow(sessions)
                }
                .store(in: &subscriptions)
            }

            isolated deinit {
                following?.cancel()
                timer.cancel()
                relaying?.close()
                server.stop()
            }

            /// Listens, and advertises when the configuration says to, returning once listening;
            /// the relay forwards from then on whenever a session is open in the app. Does nothing
            /// while it listens.
            ///
            /// - Throws: `DebugDrawerTransportError.cannotServe` when the system refuses to
            ///   listen.
            public func start() async throws(DebugDrawerTransportError) {
                try await server.start()
            }

            /// Stops listening, disconnects every viewer and stops relaying. It can start again.
            public func stop() {
                server.stop()
            }

            private func follow(_ sessions: DebugDrawerPluginTransport<DebugDrawerSessionState, DebugDrawerSessionCommand>) {
                following = Task { [weak self] in
                    for await state in sessions.snapshots() {
                        self?.sessionChanged(state)
                    }
                }
            }

            private func sessionChanged(_ state: DebugDrawerSessionState) {
                sessionState = state
                if let session = state.session {
                    timer.schedule(at: session.expires) { [weak self] in
                        self?.expiredSessionID = session.id
                        self?.update()
                    }
                } else {
                    timer.cancel()
                }
                update()
            }

            /// Relays within the open session while the server listens, and nothing otherwise.
            private func update() {
                guard isServing, let session = sessionState?.session, session.id != expiredSessionID else {
                    return endRelaying()
                }
                guard relaying?.session.id != session.id else { return }
                endRelaying()
                beginRelaying(session)
            }

            private func beginRelaying(_ session: DebugDrawerSession) {
                let app = connection.app
                let transport: DebugDrawerSidecarTransport
                do throws(DebugDrawerTransportError) {
                    transport = try DebugDrawerSidecarTransport(socketPath: app.socketPath, storeDirectory: app.storeDirectory)
                } catch {
                    Self.logger.error(
                        "Couldn't reach \(app.bundleIdentifier, privacy: .public) to relay it: \(error.localizedDescription, privacy: .public)"
                    )
                    return
                }
                let relay = SessionRelay(session: session, transport: transport)
                relaying = relay
                for id in app.capabilities where id != DebugDrawerSessions.pluginID && session.allows(id) {
                    relay.connect(id) { [weak self, weak relay] model in
                        guard let self, let relay, relaying === relay else { return }
                        registry.register(model, id: id)
                        publishStatus()
                    }
                }
                Self.logger.info("Relaying \(app.bundleIdentifier, privacy: .public) within its session")
                publishStatus()
            }

            private func endRelaying() {
                guard let relay = relaying else { return }
                relaying = nil
                for id in relay.relayedIDs {
                    registry.unregister(id: id)
                }
                relay.close()
                Self.logger.info("Stopped relaying \(self.connection.app.bundleIdentifier, privacy: .public)")
                publishStatus()
            }

            private func publishStatus() {
                var snapshot = Snapshot(app: connection.app)
                if let relaying {
                    snapshot.sessionExpires = relaying.session.expires
                    snapshot.pluginIDs = relaying.relayedIDs
                }
                guard snapshot != self.snapshot else { return }
                self.snapshot = snapshot
                status.snapshot = snapshot
            }
        }

        /// What the relay holds for one session: the transport made for it, and each plugin's
        /// connect, then its model.
        @MainActor
        private final class SessionRelay {
            let session: DebugDrawerSession
            private let transport: DebugDrawerSidecarTransport
            private var connecting: [String: Task<Void, Never>] = [:]
            private var models: [String: RelayedModel] = [:]

            init(session: DebugDrawerSession, transport: DebugDrawerSidecarTransport) {
                self.session = session
                self.transport = transport
            }

            /// The IDs relayed now, sorted.
            var relayedIDs: [String] {
                models.keys.sorted()
            }

            /// Connects to the plugin `id` and hands `relayed` its model once the app's first
            /// snapshot arrives; waits while the app serves this session none.
            func connect(_ id: String, relayed: @escaping @MainActor (RelayedModel) -> Void) {
                connecting[id] = Task { [weak self, transport] in
                    guard let plugin = try? await transport.connect(toPlugin: id, snapshot: JSONValue.self, command: JSONValue.self),
                          let self, !Task.isCancelled else { return }
                    let model = RelayedModel(transport: plugin)
                    models[id] = model
                    relayed(model)
                }
            }

            /// Stops every connect and model, and closes the transport.
            func close() {
                for task in connecting.values {
                    task.cancel()
                }
                connecting = [:]
                for model in models.values {
                    model.finish()
                }
                models = [:]
                transport.close()
            }
        }

        extension DebugDrawerSidecarRelay.Snapshot {
            /// The relay of `app` forwarding nothing.
            fileprivate init(app: DebugDrawerSidecarApp) {
                self.init(bundleIdentifier: app.bundleIdentifier, displayName: app.displayName, version: app.version, build: app.build)
            }
        }
    #else
        // The release stand-in: the same members, never listening.

        /// Release builds relay nothing: this stand-in never listens.
        @MainActor
        public final class DebugDrawerSidecarRelay: ObservableObject {
            /// The ID a viewer would read the relay's ``Snapshot`` under.
            public nonisolated static let pluginID = "DebugDrawer.SidecarRelay"

            /// The connection given.
            public let connection: DebugDrawerSidecarConnection
            /// A server that never listens.
            public let server: DebugDrawerNetworkServer

            /// A relay that never listens.
            ///
            /// - Parameters:
            ///   - connection: Kept, and never used.
            ///   - configuration: Ignored.
            public init(connection: DebugDrawerSidecarConnection, configuration: DebugDrawerNetworkServerConfiguration = .init()) {
                self.connection = connection
                server = DebugDrawerNetworkServer(registry: DebugDrawerModelRegistry(), configuration: configuration)
                let app = connection.app
                snapshot = Snapshot(bundleIdentifier: app.bundleIdentifier, displayName: app.displayName, version: app.version, build: app.build)
            }

            /// The app's identity, relaying nothing.
            @Published public private(set) var snapshot: Snapshot

            /// Does nothing.
            public func start() async throws(DebugDrawerTransportError) {}

            /// Does nothing.
            public func stop() {}
        }
    #endif
#endif
