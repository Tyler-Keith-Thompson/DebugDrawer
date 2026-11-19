import Foundation

// The viewer's half of every transport that leaves the process, written once: the socket and the
// app-group store feed it the messages they receive and give it a way to send, and it turns them
// into `DebugDrawerPluginTransport`s of the types the viewer asks for. `DebugDrawerRemote`'s
// network transport feeds it the same way, once paired (`package`, so that module reuses it).
// Everything here runs on the main actor, where the transports it hands out live; the transports'
// own I/O runs on their queues and hops here in order.

#if DEBUG
    /// The snapshots a connection has received, by plugin ID, and the transports reading them.
    @MainActor
    package final class RemoteModels {
        /// Sends a message to the models' side.
        private let send: @MainActor (TransportMessage) -> Void
        /// Whether a plugin's snapshots must be asked for (the socket), rather than arriving
        /// unasked (the store).
        private let subscribesOnConnect: Bool
        /// The newest snapshot of each plugin, as JSON.
        private var latest: [String: Data] = [:]
        /// What reads each plugin's snapshots: its transports, and connects waiting for a first
        /// one. Each is called with every new snapshot, and with `nil` when the connection closes.
        private var readers: [String: [UUID: @MainActor (Data?) -> Void]] = [:]
        /// The plugins already asked for.
        private var subscribed: Set<String> = []
        private(set) var isClosed = false

        package init(subscribesOnConnect: Bool, send: @escaping @MainActor (TransportMessage) -> Void) {
            self.subscribesOnConnect = subscribesOnConnect
            self.send = send
        }

        /// Takes in a message from the models' side: a snapshot is kept and handed to its readers;
        /// anything else is not for a viewer and is dropped.
        package func receive(_ message: TransportMessage) {
            guard message.kind == .snapshot, !isClosed, latest[message.pluginID] != message.payload else { return }
            latest[message.pluginID] = message.payload
            for reader in readers[message.pluginID, default: [:]].values {
                reader(message.payload)
            }
        }

        /// The connection is gone: transports keep their last snapshot and stop changing, and
        /// connects still waiting throw ``DebugDrawerTransportError/disconnected``.
        package func close() {
            guard !isClosed else { return }
            isClosed = true
            let all = readers.values.flatMap(\.values)
            readers = [:]
            for reader in all {
                reader(nil)
            }
        }

        /// A transport to the plugin `pluginID`, made once its first snapshot is in. It holds
        /// `connection` (the public transport that made it) while it lives, so a viewer can keep
        /// only the plugin transports and the connection stays open for them.
        package func connect<Snapshot: Codable & Equatable & Sendable, Command: Codable & Sendable>(
            toPlugin pluginID: String,
            snapshot: Snapshot.Type,
            command: Command.Type,
            holding connection: AnyObject
        ) async throws(DebugDrawerTransportError) -> DebugDrawerPluginTransport<Snapshot, Command> {
            guard !isClosed else { throw .disconnected }
            if latest[pluginID] == nil {
                guard await firstSnapshot(of: pluginID) else { throw Task.isCancelled ? .cancelled : .disconnected }
            }
            // Nothing suspends from here to the reader's registration, so no snapshot slips
            // between the one decoded and the stream.
            guard let first = latest[pluginID], let initial = try? JSONDecoder().decode(Snapshot.self, from: first) else {
                throw .mismatchedTypes
            }
            let (snapshots, continuation) = AsyncStream<Snapshot>.makeStream(bufferingPolicy: .bufferingNewest(1))
            let token = addReader(of: pluginID) { data in
                guard let data else {
                    continuation.finish()
                    return
                }
                if let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
                    continuation.yield(snapshot)
                }
            }
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.removeReader(token, of: pluginID) }
            }
            return DebugDrawerPluginTransport(initial: initial, snapshots: snapshots) { [self] command in
                withExtendedLifetime(connection) {}
                guard !isClosed, let payload = try? TransportMessage.payload(command) else { return }
                send(TransportMessage(kind: .command, pluginID: pluginID, payload: payload))
            }
        }

        /// Waits for the plugin's first snapshot, asking for it if this connection must: `false`
        /// when the connection closes or the task is cancelled first.
        private func firstSnapshot(of pluginID: String) async -> Bool {
            let (arrivals, arrived) = AsyncStream<Bool>.makeStream(bufferingPolicy: .bufferingNewest(1))
            let token = addReader(of: pluginID) { data in
                arrived.yield(data != nil)
                arrived.finish()
            }
            defer { removeReader(token, of: pluginID) }
            if subscribesOnConnect, subscribed.insert(pluginID).inserted {
                send(TransportMessage(kind: .subscribe, pluginID: pluginID))
            }
            for await isSnapshot in arrivals {
                return isSnapshot
            }
            return false
        }

        private func addReader(of pluginID: String, _ reader: @escaping @MainActor (Data?) -> Void) -> UUID {
            let token = UUID()
            readers[pluginID, default: [:]][token] = reader
            return token
        }

        private func removeReader(_ token: UUID, of pluginID: String) {
            readers[pluginID]?[token] = nil
        }
    }
#endif
