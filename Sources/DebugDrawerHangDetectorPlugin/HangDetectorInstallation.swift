#if DEBUG
    import CoreFoundation
    import DebugDrawer
    import Foundation

    /// What `HangDetector.install(threshold:)` does in debug builds.
    @MainActor
    enum HangDetectorInstallation {
        /// The monitor and the store of the first install, kept for the life of the app.
        private static var installed: (monitor: HangMonitor, store: HangStore)?
        /// The MetricKit subscriber, kept for the life of the app once subscribed.
        private static var diagnostics: (any HangDiagnosticSource)?

        static func install(threshold: Duration) {
            precondition(threshold > .zero, "The hang threshold must be positive")
            if let installed {
                installed.store.threshold = threshold
                return
            }
            let monitor = HangMonitor(
                runLoop: CFRunLoopGetMain(),
                // Called on the main thread, so the sampler it makes is the main thread's.
                sampler: MachThreadStackSampler.currentThread(),
                threshold: threshold
            ) { hang in
                // Recorded after the observer returns, rather than inside it, where the run loop
                // is about to sleep or is starting work: naming the frames and updating the
                // drawer is work of its own.
                Task { @MainActor in record(hang) }
            }
            let store = HangStore(threshold: threshold) { monitor.threshold = $0 } onUnseenCountChange: { count in
                DebugDrawer.shared.setBadge(count, forPlugin: HangDetectorPlugin.pluginID)
            }
            installed = (monitor, store)
            subscribeToDiagnostics(store)
            DebugDrawer.shared.registerGlobal(HangDetectorPlugin(store: store))
        }

        /// Keeps `hang` with its frames named, and posts a toast of it.
        private static func record(_ hang: DetectedHang) {
            guard let store = installed?.store else { return }
            let event = HangEvent(
                id: UUID(), date: hang.date, duration: hang.duration, frames: Symbolicator.lines(for: hang.addresses),
                source: .detected, isSeen: false
            )
            store.add(event)
            HangDetectorPlugin(store: store).postToast("Main thread hung for \(event.durationText)")
        }

        /// Hands MetricKit's hang diagnostics to `store`.
        private static func subscribeToDiagnostics(_ store: HangStore) {
            #if canImport(MetricKit)
                let source = MetricKitHangDiagnosticSource()
                diagnostics = source
                source.subscribe { [weak store] in store?.receive($0) }
            #endif
        }
    }
#endif
