#if DEBUG
    import Foundation
    import Network

    /// The production watcher: an `NWPathMonitor` per ``start(_:)``, as one that was cancelled
    /// can't be started again.
    @MainActor
    final class NWPathNetworkWatcher: NetworkPathWatcher {
        /// The monitor while it watches; `nil` once stopped.
        private(set) var monitor: NWPathMonitor?

        func start(_ update: @escaping @Sendable (NetworkReachability) -> Void) {
            guard monitor == nil else { return }
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in update(Self.status(of: path)) }
            monitor.start(queue: DispatchQueue(label: "com.debugdrawer.network-monitor"))
            self.monitor = monitor
        }

        func stop() {
            monitor?.cancel()
            monitor = nil
        }

        /// The path's reachability, by the interface it uses.
        nonisolated static func status(of path: NWPath) -> NetworkReachability {
            guard path.status == .satisfied else { return .offline }
            if path.usesInterfaceType(.wifi) { return .wifi }
            if path.usesInterfaceType(.cellular) { return .cellular }
            if path.usesInterfaceType(.wiredEthernet) { return .wiredEthernet }
            return .online
        }
    }
#endif
