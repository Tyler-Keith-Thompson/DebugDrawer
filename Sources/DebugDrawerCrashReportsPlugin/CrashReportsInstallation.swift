#if DEBUG
    import DebugDrawer
    import Foundation

    /// What `CrashReports.install(directory:)` does in debug builds, and what the plugin's
    /// ``CrashReportsPlugin/install(in:)`` and ``CrashReportsPlugin/uninstall(from:)`` start and
    /// stop: the crash handlers and the MetricKit subscriber, shared by every drawer the plugin is
    /// in.
    @MainActor
    enum CrashReportsInstallation {
        /// The store of each drawer the plugin is installed in, by the drawer's identity. The
        /// handlers run while there is one.
        private static var stores: [ObjectIdentifier: CrashReportStore] = [:]
        /// The store the handlers write for and MetricKit's diagnostics go to: the latest
        /// installed.
        private static var current: CrashReportStore?
        /// The MetricKit subscriber, made at the first install.
        private static var diagnostics: (any CrashDiagnosticSource)?

        static func install(directory: URL) {
            let store = CrashReportStore(directory: directory) { count in
                DebugDrawer.shared.setBadge(count, forPlugin: CrashReportsPlugin.pluginID)
            }
            // The last run's crash is read before the handlers are installed, so this run's
            // crash can't overwrite it.
            let collected = store.collectCrashFile()
            let plugin = CrashReportsPlugin(store: store)
            // The plugin installed before is removed before this one is added: its uninstall
            // stops the handlers, then this one's install starts them over its own file.
            DebugDrawer.shared.unregisterGlobal(id: plugin.id)
            DebugDrawer.shared.registerGlobal(plugin)
            plugin.setBadge(store.unseenCount)
            if let collected {
                plugin.postToast("The app crashed last time: \(collected.title)")
            }
        }

        /// Captures crashes into `store`'s directory while `drawer` holds the plugin; the first
        /// drawer installs the handlers and subscribes to MetricKit.
        static func start(_ store: CrashReportStore, in drawer: DebugDrawer) {
            stores[ObjectIdentifier(drawer)] = store
            store.load()
            capture(into: store)
        }

        /// Stops what ``start(_:in:)`` began for `drawer`, and drops `store`'s reports from
        /// memory unless another drawer shows them; the last drawer puts the handlers back and
        /// unsubscribes from MetricKit. A drawer that isn't capturing changes nothing.
        static func stop(_ store: CrashReportStore, from drawer: DebugDrawer) {
            guard stores.removeValue(forKey: ObjectIdentifier(drawer)) != nil else { return }
            if !stores.values.contains(where: { $0 === store }) {
                store.unload()
            }
            if let remaining = stores.values.first {
                if current === store { capture(into: remaining) }
                return
            }
            current = nil
            CrashCapture.uninstall()
            diagnostics?.unsubscribe()
        }

        /// Points the handlers and MetricKit's diagnostics at `store`, installing them if they
        /// aren't.
        private static func capture(into store: CrashReportStore) {
            current = store
            CrashCapture.install(crashFile: store.crashFile, appVersion: Bundle.main.appVersion)
            #if canImport(MetricKit)
                let source = diagnostics ?? MetricKitCrashDiagnosticSource()
                diagnostics = source
                source.subscribe { [weak store] in store?.receive($0) }
            #endif
        }
    }

    extension Bundle {
        /// The version and build (`1.2 (34)`), the version alone, or `nil` when the bundle names
        /// neither.
        fileprivate var appVersion: String? {
            let version = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            let build = object(forInfoDictionaryKey: "CFBundleVersion") as? String
            switch (version, build) {
            case let (version?, build?): return "\(version) (\(build))"
            case let (version?, nil): return version
            case let (nil, build?): return "(\(build))"
            case (nil, nil): return nil
            }
        }
    }
#endif
