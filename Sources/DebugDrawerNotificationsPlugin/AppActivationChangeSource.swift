#if DEBUG
    #if os(macOS)
        import AppKit
    #else
        import UIKit
    #endif
    import os

    /// Reports a possible change each time the app becomes active: on returning from Settings, from
    /// the authorization prompt, or from the background, where a notification may have been
    /// delivered. The notification center's delegate, which hears of deliveries while the app runs,
    /// is the app's, so the plugin doesn't take it; no timer polls.
    ///
    /// Copied, without its Location half, from the Permissions plugin's
    /// `SystemPermissionChangeSource`: plugins stay vertical, and a few lines duplicated cost less
    /// than a shared module.
    @MainActor
    final class AppActivationChangeSource: NotificationChangeSource {
        private static let logger = Logger(subsystem: "DebugDrawerNotificationsPlugin", category: "AppActivationChangeSource")
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
