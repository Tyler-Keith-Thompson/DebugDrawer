import Foundation

// A plugin transport a `DebugDrawerSidecarTransport` handed out is fed by a relay: it connects a
// transport of the channel in use to the plugin, reads its snapshots into the stream the plugin
// transport reads, and connects again at each switch, holding the channel's plugin transport
// while it reads, so the channel keeps sending. The first snapshot goes to the connect waiting
// for it, the later ones to the plugin transport. A channel closing, or a switch cancelling a
// connect, isn't the plugin's failure: the next channel connects again.

#if DEBUG
    /// One plugin transport a sidecar handed out, fed by a transport of the channel in use.
    @MainActor
    protocol SidecarRelay: AnyObject {
        /// Reads the plugin's snapshots from `transport` from now on, in place of the transport
        /// before.
        func attach(to transport: any DebugDrawerTransport)
        /// Stops reading, for good.
        func finish()
    }

    /// Relays one plugin's snapshots from the channel in use to the transport a sidecar handed
    /// out.
    @MainActor
    final class SidecarPluginRelay<Snapshot: Codable & Equatable & Sendable, Command: Codable & Sendable>: SidecarRelay {
        private let pluginID: String
        /// The snapshots after the first, to the plugin transport handed out.
        private let delivered: AsyncStream<Snapshot>.Continuation
        /// The first snapshot, or why there is none, to the connect waiting for it.
        private let firstOutcome: AsyncStream<Result<Snapshot, DebugDrawerTransportError>>.Continuation
        private var hasFirst = false
        /// The channel's plugin transport, held while read, so the channel keeps sending.
        private var inner: DebugDrawerPluginTransport<Snapshot, Command>?
        private var reading: Task<Void, Never>?

        init(
            pluginID: String,
            delivered: AsyncStream<Snapshot>.Continuation,
            firstOutcome: AsyncStream<Result<Snapshot, DebugDrawerTransportError>>.Continuation
        ) {
            self.pluginID = pluginID
            self.delivered = delivered
            self.firstOutcome = firstOutcome
        }

        func attach(to transport: any DebugDrawerTransport) {
            reading?.cancel()
            inner = nil
            let pluginID = pluginID
            reading = Task { [weak self] in
                let inner: DebugDrawerPluginTransport<Snapshot, Command>
                do throws(DebugDrawerTransportError) {
                    inner = try await transport.connect(toPlugin: pluginID, snapshot: Snapshot.self, command: Command.self)
                } catch {
                    self?.failed(error)
                    return
                }
                guard let self, !Task.isCancelled else { return }
                self.inner = inner
                for await snapshot in inner.snapshots() {
                    receive(snapshot)
                }
            }
        }

        func finish() {
            reading?.cancel()
            reading = nil
            inner = nil
            delivered.finish()
            firstOutcome.finish()
        }

        private func receive(_ snapshot: Snapshot) {
            guard hasFirst else {
                hasFirst = true
                firstOutcome.yield(.success(snapshot))
                firstOutcome.finish()
                return
            }
            delivered.yield(snapshot)
        }

        /// A channel closing while connecting, or a switch cancelling it, is not the plugin's
        /// failure: the next channel connects again. Anything else is.
        private func failed(_ error: DebugDrawerTransportError) {
            switch error {
            case .disconnected, .cancelled:
                return
            case .unreachable, .socketPathTooLong, .cannotServe, .mismatchedTypes, .incompatibleVersion:
                firstOutcome.yield(.failure(error))
                firstOutcome.finish()
            }
        }
    }
#endif
