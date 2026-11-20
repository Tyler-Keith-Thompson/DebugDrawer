#if DEBUG
    import DebugDrawer
    import DebugDrawerMetricKit
    import Foundation

    /// What `MetricKitPayloads.install(directory:)` and `add(json:kind:)` do in debug builds, and
    /// what the plugin's ``MetricKitPlugin/install(in:)`` and ``MetricKitPlugin/uninstall(from:)``
    /// start and stop: the subscription, shared by every drawer the plugin is in.
    @MainActor
    enum MetricKitPayloadsInstallation {
        /// The store of each drawer the plugin is installed in, by the drawer's identity. The
        /// source is subscribed while there is one.
        private static var stores: [ObjectIdentifier: MetricKitPayloadStore] = [:]
        /// The store payloads go to: the latest installed, while one is.
        private static var current: MetricKitPayloadStore?
        /// Where payloads come from, kept from the first install.
        private static var source: (any MetricKitPayloadSource)?

        /// Registers the plugin over a store in `directory`, replacing the one installed before;
        /// its install subscribes to `source`.
        ///
        /// - Parameter newSource: Where payloads come from; `nil` is MetricKit's subscriber where
        ///   it exists. Kept from the first install; a later one's is ignored.
        static func install(directory: URL, source newSource: (any MetricKitPayloadSource)? = nil) {
            let store = MetricKitPayloadStore(directory: directory) { count in
                DebugDrawer.shared.setBadge(count, forPlugin: MetricKitPlugin.pluginID)
            }
            source = source ?? newSource ?? defaultSource()
            let plugin = MetricKitPlugin(store: store)
            // The plugin installed before is removed before this one is added: its uninstall
            // unsubscribes, then this one's install subscribes over its own store.
            DebugDrawer.shared.unregisterGlobal(id: plugin.id)
            DebugDrawer.shared.registerGlobal(plugin)
            plugin.setBadge(store.unseenCount)
        }

        static func add(json: Data, kind: MetricKitPayloadKind) {
            guard let current else { return }
            receive([ReceivedMetricKitPayload(kind: kind, json: json)], in: current)
        }

        /// Keeps what the source delivers in `store` while `drawer` holds the plugin; the first
        /// drawer subscribes.
        static func start(_ store: MetricKitPayloadStore, in drawer: DebugDrawer) {
            stores[ObjectIdentifier(drawer)] = store
            current = store
            store.load()
            source = source ?? defaultSource()
            source?.subscribe { received in
                guard let current else { return }
                receive(received, in: current)
            }
        }

        /// Stops what ``start(_:in:)`` began for `drawer`, and drops `store`'s payloads from
        /// memory unless another drawer shows them; the last drawer unsubscribes. A drawer that
        /// isn't subscribed changes nothing.
        static func stop(_ store: MetricKitPayloadStore, from drawer: DebugDrawer) {
            guard stores.removeValue(forKey: ObjectIdentifier(drawer)) != nil else { return }
            if !stores.values.contains(where: { $0 === store }) {
                store.unload()
            }
            if let remaining = stores.values.first {
                if current === store { current = remaining }
                return
            }
            current = nil
            source?.unsubscribe()
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
