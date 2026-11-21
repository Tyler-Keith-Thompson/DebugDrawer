#if DEBUG
    import DebugDrawerNetwork
    import Foundation

    /// Where the interception keeps what it captures and reads the rules it applies: the stores of
    /// one Network plugin's model. ``NetworkInterception/route`` is the latest install's.
    struct NetworkRoute: Sendable {
        /// The rules requests are answered from.
        let mocks: NetworkMockRules
        /// The profiles requests are conditioned by.
        let conditions: NetworkConditions
        /// Where WebSocket traffic is recorded.
        let webSockets: NetworkWebSocketRecorder
        /// The store requests are logged in; `nil` for the shared one, which a route made off the
        /// main actor can't name.
        private let boundStore: NetworkStore?

        /// The shared stores, which `installNetwork()` fills: where the interception goes before
        /// any install, and while nothing is installed.
        static let shared = NetworkRoute(mocks: .shared, conditions: .shared, webSockets: .shared, boundStore: nil)

        /// - Parameters:
        ///   - mocks: The rules requests are answered from.
        ///   - conditions: The profiles requests are conditioned by.
        ///   - webSockets: Where WebSocket traffic is recorded.
        ///   - boundStore: The store requests are logged in; `nil` for the shared one.
        init(mocks: NetworkMockRules, conditions: NetworkConditions, webSockets: NetworkWebSocketRecorder, boundStore: NetworkStore?) {
            self.mocks = mocks
            self.conditions = conditions
            self.webSockets = webSockets
            self.boundStore = boundStore
        }

        /// The stores of `model`.
        @MainActor
        init(_ model: NetworkModel) {
            self.init(
                mocks: model.mocks.active,
                conditions: model.conditions.active,
                webSockets: model.store.webSocketRecorder,
                boundStore: model.store
            )
        }

        /// The store requests are logged in.
        @MainActor var store: NetworkStore {
            boundStore ?? .shared
        }
    }
#endif
