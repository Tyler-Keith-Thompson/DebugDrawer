#if DEBUG
    import Foundation
    import Network

    /// Reports the network's reachability in a word ("WiFi", "Offline") as it changes, from
    /// ``start(_:)`` to ``stop()``. Tests pass a fake that records when it starts and stops.
    @MainActor
    protocol NetworkPathWatcher: AnyObject {
        /// Starts watching; `update` gets the status now and after each change, on any thread.
        func start(_ update: @escaping @Sendable (String) -> Void)

        /// Stops watching; does nothing when stopped.
        func stop()
    }

    /// The production watcher: an `NWPathMonitor` per ``start(_:)``, as one that was cancelled
    /// can't be started again.
    @MainActor
    final class NWPathNetworkWatcher: NetworkPathWatcher {
        /// The monitor while it watches; `nil` once stopped.
        private(set) var monitor: NWPathMonitor?

        func start(_ update: @escaping @Sendable (String) -> Void) {
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

        /// The path's reachability in a word, by the interface it uses.
        nonisolated static func status(of path: NWPath) -> String {
            guard path.status == .satisfied else { return "Offline" }
            if path.usesInterfaceType(.wifi) { return "WiFi" }
            if path.usesInterfaceType(.cellular) { return "Cellular" }
            if path.usesInterfaceType(.wiredEthernet) { return "Ethernet" }
            return "Online"
        }
    }
#endif
