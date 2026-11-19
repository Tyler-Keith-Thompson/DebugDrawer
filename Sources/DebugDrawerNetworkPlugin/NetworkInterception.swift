#if DEBUG
    import DebugDrawer
    import Foundation
    import ObjectiveC
    import os

    /// What capturing changes in the process, started by `NetworkStore.install()` and put back
    /// by `NetworkStore.uninstall()`: the URL protocol registered for `URLSession.shared`, the
    /// `URLSessionConfiguration.protocolClasses` getter that adds it to every other session, the
    /// session factory that notes each session the app makes (``NetworkAppSessions``), and the
    /// WebSocket methods that record their traffic (``NetworkWebSocketInterception``).
    @MainActor
    enum NetworkInterception {
        // Behind a lock rather than main-actor state: URL loading and the replaced methods read it
        // on whatever thread they run, synchronously.

        /// Whether capturing was installed and then uninstalled, and not installed again. A
        /// session made while capturing keeps the plugin's URL protocol in its configuration, and
        /// a replaced method other code kept in place still runs the plugin's code, so both step
        /// aside then; before any install the protocol answers whatever session lists it.
        nonisolated static var isUninstalled: Bool {
            state.withLock { $0 == .uninstalled }
        }

        /// The drawers holding the Network plugin; capturing runs while there is one.
        private static var drawers: Set<ObjectIdentifier> = []

        /// Counts `drawer` as holding the plugin; the first one starts capturing.
        static func install(for drawer: DebugDrawer) {
            drawers.insert(ObjectIdentifier(drawer))
            NetworkStore.shared.install()
        }

        /// Uncounts `drawer`; once no drawer holds the plugin, capturing stops.
        static func uninstall(for drawer: DebugDrawer) {
            guard drawers.remove(ObjectIdentifier(drawer)) != nil, drawers.isEmpty else { return }
            NetworkStore.shared.uninstall()
        }

        private enum State {
            case neverInstalled, capturing, uninstalled
        }

        private nonisolated static let state = OSAllocatedUnfairLock(initialState: State.neverInstalled)
        private static let replacements = MethodReplacements()

        static func start() {
            state.withLock { $0 = .capturing }
            URLProtocol.registerClass(DebugNetworkProtocol.self)
            if let methods = URLSessionConfiguration.protocolClassesMethods {
                replacements.exchange(methods.getter, with: methods.replacement)
            }
            // Note each session the app makes, so its requests are sent with its configuration.
            NetworkAppSessions.install()
            // WebSocket tasks bypass URL protocols, so their traffic is recorded on the tasks.
            NetworkWebSocketInterception.install()
        }

        static func stop() {
            state.withLock { $0 = .uninstalled }
            URLProtocol.unregisterClass(DebugNetworkProtocol.self)
            replacements.restore()
            NetworkAppSessions.uninstall()
            NetworkWebSocketInterception.uninstall()
        }
    }
#endif
