#if DEBUG
    #if os(macOS)
        import AppKit
    #else
        import UIKit
    #endif
    import os

    /// Reports a possible change each time the app becomes active: on returning from the
    /// background, where the system may have run a task and so used up its request, or from the
    /// debugger, where a simulated launch may have. `BGTaskScheduler` reports no change of its own,
    /// so no timer polls it.
    ///
    /// Copied from the Notifications plugin's `AppActivationChangeSource`: plugins stay vertical,
    /// and a few lines duplicated cost less than a shared module.
    @MainActor
    final class AppActivationChangeSource: BackgroundTaskChangeSource {
        private static let logger = Logger(subsystem: "DebugDrawerBackgroundTasksPlugin", category: "AppActivationChangeSource")
        private var observer: (any NSObjectProtocol)?

        func observe(_ onChange: @escaping @MainActor () async -> Void) {
            stop()
            observer = NotificationCenter.default.addObserver(forName: Self.didBecomeActive, object: nil, queue: .main) { _ in
                // Posted on the main thread and delivered on the main queue.
                MainActor.assumeIsolated {
                    Self.logger.debug("The app became active")
                    Task { await onChange() }
                }
            }
        }

        func stop() {
            guard let observer else { return }
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }

        /// Whether the source is observing the app becoming active.
        var isObserving: Bool {
            observer != nil
        }

        private static var didBecomeActive: Notification.Name {
            #if os(macOS)
                NSApplication.didBecomeActiveNotification
            #else
                UIApplication.didBecomeActiveNotification
            #endif
        }
    }
#endif
