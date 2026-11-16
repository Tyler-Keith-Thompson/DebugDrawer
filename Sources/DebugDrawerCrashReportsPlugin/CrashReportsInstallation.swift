#if DEBUG
    import DebugDrawer
    import Foundation

    /// What `CrashReports.install(directory:)` does in debug builds.
    @MainActor
    enum CrashReportsInstallation {
        /// The MetricKit subscriber, kept for the life of the app once subscribed.
        private static var diagnostics: (any CrashDiagnosticSource)?

        static func install(directory: URL) {
            let store = CrashReportStore(directory: directory) { count in
                DebugDrawer.shared.setBadge(count, forPlugin: CrashReportsPlugin.pluginID)
            }
            // The last run's crash is read before the handlers are installed, so this run's
            // crash can't overwrite it.
            let collected = store.collectCrashFile()
            CrashCapture.install(crashFile: store.crashFile, appVersion: Bundle.main.appVersion)
            subscribeToDiagnostics(store)

            let plugin = CrashReportsPlugin(store: store)
            DebugDrawer.shared.unregisterGlobal(id: plugin.id)
            DebugDrawer.shared.registerGlobal(plugin)
            plugin.setBadge(store.unseenCount)
            if let collected {
                plugin.postToast("The app crashed last time: \(collected.title)")
            }
        }

        /// Hands MetricKit's crash diagnostics to `store`, the store of the latest install.
        private static func subscribeToDiagnostics(_ store: CrashReportStore) {
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
