#if DEBUG
    import DebugDrawer
    import Foundation
    import ObjectiveC
    import os

    // URL loading makes the URL protocol by its class and the replaced methods run in the app's own
    // calls, so neither knows which drawer installed the plugin; they read the route here, as installs
    // come and go. The drawer that installed the plugin last gets the requests and sets the mocks and
    // conditions they meet: a drawer of a test's own, installed while the app's drawer holds the
    // plugin too, sees its own requests, and the app's drawer gets them again once that drawer removes
    // the plugin. Rejected: the first install keeping the route (a drawer installed later would never
    // see a request), and every installed store logging each request (each request kept twice, and
    // two drawers' mock rules and conditions with no order between them).

    /// What capturing changes in the process, started by `NetworkStore.install()` and put back
    /// by `NetworkStore.uninstall()`: the URL protocol registered for `URLSession.shared`, the
    /// `URLSessionConfiguration.protocolClasses` getter that adds it to every other session, the
    /// session factory that notes each session the app makes (``NetworkAppSessions``), and the
    /// WebSocket methods that record their traffic (``NetworkWebSocketInterception``). It also
    /// holds the route they all capture into (``route``).
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

        /// Where a request starting now is logged and finds its mocks and conditions, and where
        /// WebSocket traffic is recorded: the stores of the drawer that installed the plugin last,
        /// or the shared ones while none holds it. Setting it sends what starts from then on to the
        /// route set, until the next install or uninstall sets it again.
        nonisolated static var route: NetworkRoute {
            get { boundRoute.withLock { $0 } }
            set { boundRoute.withLock { $0 = newValue } }
        }

        /// The drawers holding the Network plugin, in the order they installed it, each with its
        /// plugin's route; capturing runs while there is one.
        private static var installations: [(drawer: ObjectIdentifier, route: NetworkRoute)] = []
        private nonisolated static let boundRoute = OSAllocatedUnfairLock(initialState: NetworkRoute.shared)

        /// Counts `drawer` as holding the plugin over `model`, whose stores capture from now on;
        /// the first install starts capturing. A drawer that holds it already changes nothing.
        static func install(_ model: NetworkModel, for drawer: DebugDrawer) {
            let id = ObjectIdentifier(drawer)
            guard !installations.contains(where: { $0.drawer == id }) else { return }
            let route = NetworkRoute(model)
            installations.append((id, route))
            Self.route = route
            model.store.install()
        }

        /// Uncounts `drawer`; the drawer that installed the plugin before it captures again. A
        /// store no drawer holds any more forgets what it captured, and once no drawer holds the
        /// plugin, capturing stops.
        static func uninstall(for drawer: DebugDrawer) {
            guard let index = installations.firstIndex(where: { $0.drawer == ObjectIdentifier(drawer) }) else { return }
            let store = installations.remove(at: index).route.store
            route = installations.last?.route ?? .shared
            if installations.isEmpty {
                store.uninstall()
            } else if !installations.contains(where: { $0.route.store === store }) {
                store.uninstall(stoppingCapture: false)
            }
        }

        private enum State {
            case neverInstalled, capturing, uninstalled
        }

        private nonisolated static let state = OSAllocatedUnfairLock(initialState: State.neverInstalled)
        private static let replacements = MethodReplacements()

        /// Starts capturing, unless it runs already.
        static func start() {
            guard state.withLock({ $0 }) != .capturing else { return }
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

        /// Puts back what ``start()`` changed, unless capturing isn't running.
        static func stop() {
            guard state.withLock({ $0 }) == .capturing else { return }
            state.withLock { $0 = .uninstalled }
            URLProtocol.unregisterClass(DebugNetworkProtocol.self)
            replacements.restore()
            NetworkAppSessions.uninstall()
            NetworkWebSocketInterception.uninstall()
        }
    }
#endif
