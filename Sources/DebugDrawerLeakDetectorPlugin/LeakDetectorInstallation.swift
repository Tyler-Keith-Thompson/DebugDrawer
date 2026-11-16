#if DEBUG
    import DebugDrawer
    import Foundation

    /// What `LeakDetector.install()` and `trackLifetime(of:maxCount:)` do in debug builds.
    @MainActor
    enum LeakDetectorInstallation {
        /// The suspects the drawer shows, made with the monitor.
        static let store = LeakStore { count in
            if isInstalled {
                DebugDrawer.shared.setBadge(count, forPlugin: LeakDetectorPlugin.pluginID)
            }
        }

        /// Made at the first object tracked or the install, whichever comes first, and kept for the
        /// life of the app.
        static let monitor = LeakMonitor(turns: MainRunLoopTurnSource()) { change in
            store.update(change.suspects)
            guard isInstalled else { return }
            let plugin = LeakDetectorPlugin(store: store)
            for suspect in change.flagged where !store.isIgnored(suspect) {
                plugin.postToast(suspect.toastMessage)
            }
        }

        /// Whether the plugin is in the drawer, which is when suspects raise its badge and post
        /// toasts.
        private static var isInstalled = false

        static func install() {
            guard !isInstalled else { return }
            isInstalled = true
            DebugDrawer.shared.registerGlobal(LeakDetectorPlugin(store: store))
            store.update(monitor.suspects)
            ViewControllerLifecycle.install { viewController in
                monitor.dismiss(viewController, isDetached: ViewControllerLifecycle.isDetached)
            }
        }

        /// Counts `object` in the monitor, made on the main actor if it isn't yet.
        nonisolated static func track(_ object: AnyObject, maxCount: Int) {
            LeakMonitor.track(object, maxCount: maxCount) { monitor }
        }
    }
#endif
