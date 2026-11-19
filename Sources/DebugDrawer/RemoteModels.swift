import Foundation
import os

// The viewer's half of every transport that leaves the process, written once: the socket and the
// app-group store feed it the messages they receive and give it a way to send, and it turns them
// into `DebugDrawerPluginTransport`s of the types the viewer asks for. `DebugDrawerRemote`'s
// network transport feeds it the same way, once paired (`package`, so that module reuses it).
// Everything here runs on the main actor, where the transports it hands out live; the transports'
// own I/O runs on their queues and hops here in order.
//
// On a stream it says hello first and sends only what it agreed on with the app (`TransportPeer`):
// a command only to an app that takes them, and an unsubscribe, once a plugin's last transport is
// released, only to an app that has the capability. An app it shares no protocol version with
// closes the connection, and every connect waiting or made after it throws `incompatibleVersion`.

#if DEBUG
    /// The snapshots a connection has received, by plugin ID, and the transports reading them.
    @MainActor
    package final class RemoteModels {
        private static let logger = Logger(subsystem: "DebugDrawer", category: "RemoteModels")

        /// What carries the messages: on a stream, a plugin's snapshots must be asked for; the
        /// store's arrive unasked.
        private let link: TransportLink
        /// Sends a message to the models' side.
        private let send: @MainActor (TransportMessage) -> Void
        /// Ends the connection, when the app shares no protocol version with this build.
        private let disconnect: @MainActor () -> Void
        /// The newest snapshot of each plugin, as JSON.
        private var latest: [String: Data] = [:]
        /// What reads each plugin's snapshots: its transports, and connects waiting for a first
        /// one. Each is called with every new snapshot, and with `nil` when the connection closes.
        private var readers: [String: [UUID: @MainActor (Data?) -> Void]] = [:]
        /// The plugins asked for, and not since released.
        private var subscribed: Set<String> = []
        /// The app, as its messages describe it.
        package private(set) var peer = TransportPeer()
        /// Why the connection closed, once it has: what a connect throws from then on.
        private var closedBecause: DebugDrawerTransportError?

        /// The viewer's side of a connection over `link`; on a stream it says hello at once.
        ///
        /// - Parameters:
        ///   - link: What carries the messages.
        ///   - send: Sends a message to the models' side.
        ///   - disconnect: Ends the connection: called when the app shares no protocol version
        ///     with this build.
        package init(
            link: TransportLink,
            send: @escaping @MainActor (TransportMessage) -> Void,
            disconnect: @escaping @MainActor () -> Void = {}
        ) {
            self.link = link
            self.send = send
            self.disconnect = disconnect
            if link == .stream {
                send(.hello(.current))
            }
        }

        var isClosed: Bool {
            closedBecause != nil
        }

        /// Takes in a message from the models' side: a hello is kept, a snapshot is kept and
        /// handed to its readers, and anything else is not for a viewer and is dropped.
        package func receive(_ message: TransportMessage) {
            guard !isClosed else { return }
            switch peer.admit(message) {
            case .agreed, .ignored:
                return
            case .incompatible:
                close(because: .incompatibleVersion)
                disconnect()
            case let .deliver(message):
                // On a stream, a snapshot of a plugin released since arrived after its
                // unsubscribe left: dropped, so a later connect asks afresh rather than reading it.
                guard message.kind == .snapshot,
                      link == .store || subscribed.contains(message.pluginID),
                      latest[message.pluginID] != message.payload else { return }
                latest[message.pluginID] = message.payload
                for reader in readers[message.pluginID, default: [:]].values {
                    reader(message.payload)
                }
            }
        }

        /// The connection is gone: transports keep their last snapshot and stop changing, and
        /// connects still waiting throw ``DebugDrawerTransportError/disconnected``.
        package func close() {
            close(because: .disconnected)
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
            if let closedBecause { throw closedBecause }
            if latest[pluginID] == nil {
                guard await firstSnapshot(of: pluginID) else {
                    throw Task.isCancelled ? .cancelled : closedBecause ?? .disconnected
                }
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
                Task { @MainActor in self?.release(token, of: pluginID) }
            }
            return DebugDrawerPluginTransport(initial: initial, snapshots: snapshots) { [self] command in
                withExtendedLifetime(connection) {}
                guard !isClosed, let payload = try? TransportMessage.payload(command) else { return }
                guard peer.uses(.commands) else {
                    Self.logger.notice("Dropped a command for \(pluginID, privacy: .public): the app doesn't take commands")
                    return
                }
                send(TransportMessage(kind: .command, pluginID: pluginID, payload: payload))
            }
        }

        /// Marks the connection closed for `reason`, once: every reader hears `nil`.
        private func close(because reason: DebugDrawerTransportError) {
            guard !isClosed else { return }
            closedBecause = reason
            let all = readers.values.flatMap(\.values)
            readers = [:]
            for reader in all {
                reader(nil)
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
            if link == .stream, subscribed.insert(pluginID).inserted {
                send(TransportMessage(kind: .subscribe, pluginID: pluginID))
            }
            for await isSnapshot in arrivals {
                return isSnapshot
            }
            return false
        }

        /// A plugin transport went: when it was the plugin's last reader on a stream, tells an app
        /// that can hear it to stop sending the plugin's snapshots.
        private func release(_ token: UUID, of pluginID: String) {
            removeReader(token, of: pluginID)
            guard link == .stream, !isClosed, readers[pluginID, default: [:]].isEmpty, peer.uses(.unsubscribe),
                  subscribed.remove(pluginID) != nil else { return }
            latest[pluginID] = nil
            send(TransportMessage(kind: .unsubscribe, pluginID: pluginID))
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
