#if DEBUG
    import CoreLocation

    /// Location, through Core Location. Its request call returns at once, so the manager's
    /// delegate hears the answer.
    @MainActor
    final class LocationPermissionReader: NSObject, SystemPermissionReader, @preconcurrency CLLocationManagerDelegate {
        /// Reading the status needs an instance; creating one doesn't prompt. Created on the
        /// main thread, so its delegate is called there, as its isolation needs.
        private var manager: CLLocationManager {
            if let createdManager { return createdManager }
            let manager = CLLocationManager()
            manager.delegate = self
            createdManager = manager
            return manager
        }

        /// The manager once a read or request made it, until ``stop()``.
        private var createdManager: CLLocationManager?
        private var answered: CheckedContinuation<Void, Never>?

        /// Whether the reader holds a manager.
        var isHoldingManager: Bool {
            createdManager != nil
        }

        func stop() {
            createdManager?.delegate = nil
            createdManager = nil
            answered?.resume()
            answered = nil
        }

        func status(of _: DeclaredPermission) async -> PermissionStatus {
            PermissionStatus(manager.authorizationStatus)
        }

        /// Asks for when-in-use access and returns once the user has answered.
        func request(_: DeclaredPermission) async {
            guard answered == nil, manager.authorizationStatus == .notDetermined else { return }
            await withCheckedContinuation { continuation in
                answered = continuation
                manager.requestWhenInUseAuthorization()
            }
        }

        func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
            // Also called once when the manager is created, before anything is asked.
            guard manager.authorizationStatus != .notDetermined else { return }
            answered?.resume()
            answered = nil
        }
    }

    extension PermissionStatus {
        init(_ status: CLAuthorizationStatus) {
            switch status {
            case .notDetermined: self = .notDetermined
            case .restricted: self = .restricted
            case .denied: self = .denied
            case .authorizedAlways: self = .authorizedAlways
            case .authorizedWhenInUse: self = .authorizedWhenInUse
            @unknown default: self = .unknown(rawValue: Int(status.rawValue))
            }
        }
    }
#endif
