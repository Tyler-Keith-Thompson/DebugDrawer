#if DEBUG
    import DebugDrawer
    import Foundation

    /// What `MetricKitPayloads.install(directory:)` and `add(json:kind:)` do in debug builds.
    @MainActor
    enum MetricKitPayloadsInstallation {
        /// The store of the latest install, which payloads go to.
        private static var store: MetricKitPayloadStore?
        /// The subscriber, kept for the life of the app once subscribed.
        private static var source: (any MetricKitPayloadSource)?

        /// Registers the plugin over a store in `directory` and hands it what `source` delivers.
        ///
        /// - Parameter newSource: Where payloads come from; `nil` is MetricKit's subscriber where
        ///   it exists. Kept from the first install; a later one's is ignored.
        static func install(directory: URL, source newSource: (any MetricKitPayloadSource)? = nil) {
            let store = MetricKitPayloadStore(directory: directory) { count in
                DebugDrawer.shared.setBadge(count, forPlugin: MetricKitPlugin.pluginID)
            }
            Self.store = store
            let plugin = MetricKitPlugin(store: store)
            DebugDrawer.shared.unregisterGlobal(id: plugin.id)
            DebugDrawer.shared.registerGlobal(plugin)
            plugin.setBadge(store.unseenCount)
            source = source ?? newSource ?? defaultSource()
            source?.subscribe { [weak store] received in
                guard let store else { return }
                receive(received, in: store)
            }
        }

        static func add(json: Data, kind: MetricKitPayloadKind) {
            guard let store else { return }
            receive([ReceivedMetricKitPayload(kind: kind, json: json)], in: store)
        }

        /// Keeps `received` in `store` and posts a toast for each payload it hadn't kept.
        private static func receive(_ received: [ReceivedMetricKitPayload], in store: MetricKitPayloadStore) {
            let plugin = MetricKitPlugin(store: store)
            for payload in store.receive(received) {
                // Posts from one plugin coalesce into one toast that counts them.
                plugin.postToast("New MetricKit payload: \(payload.kind.title.lowercased())")
            }
        }

        private static func defaultSource() -> (any MetricKitPayloadSource)? {
            #if canImport(MetricKit)
                MetricManagerPayloadSource()
            #else
                nil
            #endif
        }
    }
#endif
