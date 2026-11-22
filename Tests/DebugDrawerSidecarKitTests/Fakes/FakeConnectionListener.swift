#if DEBUG && canImport(DebugDrawerRemote)
    import DebugDrawer
    import DebugDrawerRemote
    import Network

    /// A listener that listens on nothing: it keeps each request it gets, says it listens on
    /// `port`, and counts cancels.
    @MainActor
    final class FakeConnectionListener: ConnectionListener {
        private(set) var requests: [ListenerRequest] = []
        private(set) var cancelCount = 0
        let port: UInt16

        init(port: UInt16 = 4242) {
            self.port = port
        }

        func listen(
            _ request: ListenerRequest,
            accept: @escaping @Sendable (NWConnection) -> Void
        ) async throws(DebugDrawerTransportError) -> UInt16 {
            requests.append(request)
            return port
        }

        func cancel() {
            cancelCount += 1
        }
    }
#endif
