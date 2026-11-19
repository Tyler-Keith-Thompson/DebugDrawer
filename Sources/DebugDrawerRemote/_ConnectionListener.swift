import DebugDrawer
import Network

// Listens with Network.framework's `NWListener`, which also advertises the Bonjour service, where
// a POSIX socket would need the C dns_sd API beside it. A listener that waits (no network yet, or
// the port taken) is cancelled and reported as refused, rather than left retrying.

#if DEBUG
    /// Network.framework's `NWListener`.
    @MainActor
    final class _ConnectionListener: ConnectionListener {
        private var listener: NWListener?

        // A server dropped without `stop()` stops listening with it.
        isolated deinit {
            listener?.cancel()
        }

        func listen(
            _ request: ListenerRequest,
            accept: @escaping @Sendable (NWConnection) -> Void
        ) async throws(DebugDrawerTransportError) -> UInt16 {
            let parameters = NWParameters.tcp
            let port = request.port.flatMap(NWEndpoint.Port.init(rawValue:)) ?? .any
            let listener: NWListener
            do {
                if request.loopbackOnly {
                    parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: port)
                    listener = try NWListener(using: parameters)
                } else {
                    listener = try NWListener(using: parameters, on: port)
                }
            } catch {
                throw .cannotServe
            }
            if let advertisement = request.advertisement {
                listener.service = DebugDrawerBonjourService.listenerService(name: advertisement.name, txtRecord: advertisement.txtRecord)
            }
            listener.newConnectionHandler = accept
            self.listener = listener
            let (states, state) = AsyncStream<UInt16?>.makeStream(bufferingPolicy: .bufferingNewest(1))
            listener.stateUpdateHandler = { update in
                switch update {
                case .ready:
                    state.yield(listener.port?.rawValue)
                case .waiting, .failed, .cancelled:
                    state.yield(nil)
                default:
                    break
                }
            }
            listener.start(queue: DispatchQueue(label: "DebugDrawerRemote.ConnectionListener"))
            for await port in states {
                guard let port else { break }
                return port
            }
            listener.cancel()
            self.listener = nil
            throw .cannotServe
        }

        func cancel() {
            listener?.cancel()
            listener = nil
        }
    }
#endif
