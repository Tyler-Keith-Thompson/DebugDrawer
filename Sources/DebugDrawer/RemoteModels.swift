import DebugDrawerReceiver
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
//
// Each command goes with an ID. To an app that acknowledges commands, it is kept until its
// acknowledgement arrives, in the order sent, so a sidecar whose stream ends can send what wasn't
// acknowledged through the store (`DebugDrawerSidecarTransport`); the app performs an ID once,
// however it arrives. To an app that doesn't, nothing is kept, as nothing would ever take it off.

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
        /// The commands sent to an app that acknowledges them and not yet acknowledged, oldest
        /// first.
        private(set) var unacknowledgedCommands: [TransportMessage] = []
        /// Whether the app has said a hello this build agrees with.
        private var hasAgreed = false
        /// Who waits for ``handshake()``: each hears whether the app said a hello this build
        /// agrees with before the connection closed.
        private var handshakeWaiters: [AsyncStream<Bool>.Continuation] = []

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
            case .agreed:
                hasAgreed = true
                finishHandshake(true)
            case .ignored:
                return
            case .incompatible:
                close(because: .incompatibleVersion)
                disconnect()
            case let .deliver(message) where message.kind == .acknowledgement:
                unacknowledgedCommands.removeAll { $0.commandID == message.commandID }
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

        /// Waits for the app's hello: `true` once it said one this build agrees with, `false` when
        /// the connection closes, or the waiting task is cancelled, first. An app of version 1
        /// says none, so this waits until the connection closes.
        func handshake() async -> Bool {
            if hasAgreed { return true }
            if isClosed { return false }
            let (agreement, agreed) = AsyncStream<Bool>.makeStream(bufferingPolicy: .bufferingNewest(1))
            handshakeWaiters.append(agreed)
            for await isAgreed in agreement {
                return isAgreed
            }
            return false
        }

        /// Sends `message`, a command with an ID, keeping it until acknowledged when the app
        /// acknowledges commands on a stream: `false`, and nothing sent, once the connection is
        /// closed.
        func send(command message: TransportMessage) -> Bool {
            guard !isClosed else { return false }
            guard peer.uses(.commands) else {
                Self.logger.notice("Dropped a command for \(message.pluginID, privacy: .public): the app doesn't take commands")
                return true
            }
            // The store acknowledges nothing: the app removing the file is what takes a command.
            if link == .stream, peer.uses(.acknowledgements) {
                unacknowledgedCommands.append(message)
            }
            send(message)
            return true
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
                guard let payload = try? TransportMessage.payload(command) else { return }
                _ = send(command: TransportMessage(kind: .command, pluginID: pluginID, payload: payload, commandID: UUID()))
            }
        }

        /// Marks the connection closed for `reason`, once: every reader hears `nil`.
        private func close(because reason: DebugDrawerTransportError) {
            guard !isClosed else { return }
            closedBecause = reason
            finishHandshake(false)
            let all = readers.values.flatMap(\.values)
            readers = [:]
            for reader in all {
                reader(nil)
            }
        }

        private func finishHandshake(_ isAgreed: Bool) {
            let waiters = handshakeWaiters
            handshakeWaiters = []
            for waiter in waiters {
                waiter.yield(isAgreed)
                waiter.finish()
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
