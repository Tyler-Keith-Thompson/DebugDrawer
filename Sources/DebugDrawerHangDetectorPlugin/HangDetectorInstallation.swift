#if DEBUG
    import CoreFoundation
    import DebugDrawer
    import DebugDrawerHangDetector
    import Foundation

    /// What `HangDetector.install(threshold:)` does in debug builds, and what the plugin's
    /// ``HangDetectorPlugin/install(in:)`` and ``HangDetectorPlugin/uninstall(from:)`` start and
    /// stop: the monitor on the main run loop and the MetricKit subscriber, shared by every drawer
    /// the plugin is in.
    @MainActor
    enum HangDetectorInstallation {
        /// The store `install(threshold:)` made first, kept so a later call changes its threshold.
        private(set) static var installedStore: HangStore?
        /// The store of each drawer the plugin is installed in, by the drawer's identity. The
        /// monitor runs while there is one.
        private static var stores: [ObjectIdentifier: HangStore] = [:]
        /// The store hangs are recorded in: the latest installed.
        private static var current: HangStore?
        /// Watches the main thread while a drawer holds the plugin.
        private static var monitor: HangMonitor?
        /// The MetricKit subscriber, made at the first install.
        private static var diagnostics: (any HangDiagnosticSource)?

        /// Installs over `threshold`, which `HangDetector.install(threshold:)` has checked is
        /// positive.
        static func install(threshold: Duration) {
            let store = installedStore ?? HangStore(threshold: threshold) { monitor?.threshold = $0 }
            installedStore = store
            store.threshold = threshold
            // Registered already, this adds nothing; after the plugin was removed, it adds it again.
            DebugDrawer.shared.registerGlobal(HangDetectorPlugin(store: store))
        }

        /// Records hangs into `store` while `drawer` holds the plugin, and badges `drawer` with its
        /// unseen hangs; the first drawer starts the monitor and subscribes to MetricKit.
        static func start(_ store: HangStore, in drawer: DebugDrawer) {
            stores[ObjectIdentifier(drawer)] = store
            current = store
            store.badge.show(store.unseenCount, in: drawer)
            if let monitor {
                monitor.threshold = store.threshold
                return
            }
            monitor = HangMonitor(
                runLoop: CFRunLoopGetMain(),
                // Called on the main thread, so the sampler it makes is the main thread's.
                sampler: MachThreadStackSampler.currentThread(),
                threshold: store.threshold
            ) { hang in
                // Recorded after the observer returns, rather than inside it, where the run loop
                // is about to sleep or is starting work: naming the frames and updating the
                // drawer is work of its own.
                Task { @MainActor in record(hang) }
            }
            #if canImport(MetricKit)
                let source = diagnostics ?? MetricKitHangDiagnosticSource()
                diagnostics = source
                source.subscribe { current?.receive($0) }
            #endif
        }

        /// Stops what ``start(_:in:)`` began for `drawer`, clearing its badge there, and forgets
        /// `store`'s hangs unless another drawer shows them; the last drawer stops the monitor (its
        /// observers removed, its watcher thread ended) and unsubscribes from MetricKit. A drawer
        /// that isn't recording changes nothing.
        static func stop(_ store: HangStore, from drawer: DebugDrawer) {
            guard stores.removeValue(forKey: ObjectIdentifier(drawer)) != nil else { return }
            store.badge.remove(from: drawer)
            if !stores.values.contains(where: { $0 === store }) {
                store.clear()
            }
            if let remaining = stores.values.first {
                if current === store {
                    current = remaining
                    monitor?.threshold = remaining.threshold
                }
                return
            }
            current = nil
            monitor?.stop()
            monitor = nil
            diagnostics?.unsubscribe()
        }

        /// Keeps `hang` with its frames named, and posts a toast of it; dropped once no drawer
        /// holds the plugin.
        private static func record(_ hang: DetectedHang) {
            guard let store = current else { return }
            let event = HangEvent(
                id: UUID(), date: hang.date, duration: hang.duration, frames: Symbolicator.lines(for: hang.addresses),
                source: .detected, isSeen: false
            )
            store.add(event)
            HangDetectorPlugin(store: store).postToast("Main thread hung for \(event.durationText)")
        }
    }
#endif
