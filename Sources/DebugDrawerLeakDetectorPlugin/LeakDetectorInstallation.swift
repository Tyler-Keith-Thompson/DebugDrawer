#if DEBUG
    import DebugDrawer
    import Foundation
    import os

    /// What `LeakDetector.install()` and `trackLifetime(of:maxCount:)` do in debug builds, and what
    /// the plugin's ``LeakDetectorPlugin/install(in:)`` and ``LeakDetectorPlugin/uninstall(from:)``
    /// start and stop: the `viewDidDisappear` exchange and the monitor, shared by every drawer the
    /// plugin is in.
    @MainActor
    enum LeakDetectorInstallation {
        /// The suspects the drawer shows, made with the monitor.
        static let store = LeakStore()

        /// Made at the first object tracked or the install, whichever comes first, and dropped by
        /// the last uninstall.
        private(set) static var monitor: LeakMonitor?

        /// The drawers the plugin is installed in, by identity; suspects post toasts while there is
        /// one.
        private static var drawers: Set<ObjectIdentifier> = []

        private static var isInstalled: Bool {
            !drawers.isEmpty
        }

        // Behind a lock rather than main-actor state: `trackLifetime(of:maxCount:)` reads it on
        // whatever thread it is called from, synchronously.
        /// Whether the plugin was installed and then uninstalled, and not installed again: an
        /// object tracked then is not counted, so tracking costs a lock and nothing more.
        private nonisolated static let isUninstalled = OSAllocatedUnfairLock(initialState: false)

        static func install() {
            // Registered already, this adds nothing; after the plugin was removed, it adds it again.
            DebugDrawer.shared.registerGlobal(LeakDetectorPlugin(store: store))
        }

        /// Watches the app's view controllers while `drawer` holds the plugin, and badges `drawer`
        /// with the suspects not ignored; the first drawer exchanges `viewDidDisappear` and shows
        /// what the monitor found so far.
        static func start(in drawer: DebugDrawer) {
            let isFirst = drawers.isEmpty
            drawers.insert(ObjectIdentifier(drawer))
            store.badge.show(store.visibleSuspects.count, in: drawer)
            guard isFirst else { return }
            isUninstalled.withLock { $0 = false }
            let monitor = trackingMonitor()
            store.update(monitor?.suspects ?? [])
            ViewControllerLifecycle.install { viewController in
                monitor?.dismiss(viewController, isDetached: ViewControllerLifecycle.isDetached)
            }
        }

        /// Stops what ``start(in:)`` began for `drawer`, clearing its badge there; the last drawer
        /// puts `viewDidDisappear` back, stops the monitor and forgets its suspects and the objects
        /// it counted. A drawer that isn't watching changes nothing.
        static func stop(from drawer: DebugDrawer) {
            guard drawers.remove(ObjectIdentifier(drawer)) != nil else { return }
            store.badge.remove(from: drawer)
            guard drawers.isEmpty else { return }
            isUninstalled.withLock { $0 = true }
            ViewControllerLifecycle.uninstall()
            monitor?.stop()
            monitor = nil
            store.update([])
        }

        /// Counts `object` in the monitor, made on the main actor if it isn't yet; does nothing
        /// once the plugin is uninstalled.
        nonisolated static func track(_ object: AnyObject, maxCount: Int) {
            guard !isUninstalled.withLock({ $0 }) else { return }
            LeakMonitor.track(object, maxCount: maxCount) { trackingMonitor() }
        }

        /// The monitor, made now if it isn't yet, or `nil` once the plugin is uninstalled.
        private static func trackingMonitor() -> LeakMonitor? {
            if let monitor {
                return monitor
            }
            guard !isUninstalled.withLock({ $0 }) else { return nil }
            let made = LeakMonitor(turns: MainRunLoopTurnSource()) { change in
                store.update(change.suspects)
                guard isInstalled else { return }
                let plugin = LeakDetectorPlugin(store: store)
                for suspect in change.flagged where !store.isIgnored(suspect) {
                    plugin.postToast(suspect.toastMessage)
                }
            }
            monitor = made
            return made
        }
    }
#endif
