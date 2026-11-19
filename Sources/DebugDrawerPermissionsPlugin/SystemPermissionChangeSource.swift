#if DEBUG
    #if os(macOS)
        import AppKit
    #else
        import UIKit
    #endif
    import CoreLocation
    import os

    /// Reports a possible change each time the app becomes active, as it does on returning from
    /// Settings or from a system prompt, and each time Location reports a change of its
    /// authorization. The other frameworks report no change of their own, so becoming active is
    /// when they are read again; no timer polls them.
    @MainActor
    final class SystemPermissionChangeSource: NSObject, PermissionChangeSource, @preconcurrency CLLocationManagerDelegate {
        private static let logger = Logger(subsystem: "DebugDrawerPermissionsPlugin", category: "SystemPermissionChangeSource")
        /// Created only once observed, so a source never observed asks Location nothing.
        private var locationManager: CLLocationManager?
        private var observer: (any NSObjectProtocol)?
        private var onChange: (@MainActor () async -> Void)?

        func observe(_ onChange: @escaping @MainActor () async -> Void) {
            stop()
            self.onChange = onChange
            observer = NotificationCenter.default.addObserver(forName: Self.didBecomeActive, object: nil, queue: .main) { [weak self] _ in
                // Posted on the main thread and delivered on the main queue.
                MainActor.assumeIsolated {
                    Self.logger.debug("The app became active")
                    self?.changed()
                }
            }
            // No queue to pass: the delegate is called on the thread that created the manager,
            // the main one.
            let manager = CLLocationManager()
            manager.delegate = self
            locationManager = manager
        }

        func stop() {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
                self.observer = nil
            }
            locationManager?.delegate = nil
            locationManager = nil
            onChange = nil
        }

        /// Whether the source is observing the app becoming active and Location's authorization.
        var isObserving: Bool {
            observer != nil || locationManager != nil
        }

        func locationManagerDidChangeAuthorization(_: CLLocationManager) {
            Self.logger.debug("Location reported a change of its authorization")
            changed()
        }

        private func changed() {
            guard let onChange else { return }
            Task { await onChange() }
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
