#if DEBUG
    import AppTrackingTransparency

    /// Tracking, through App Tracking Transparency.
    struct TrackingPermissionReader: SystemPermissionReader {
        func status(of _: DeclaredPermission) async -> PermissionStatus {
            PermissionStatus(ATTrackingManager.trackingAuthorizationStatus)
        }

        func request(_: DeclaredPermission) async {
            _ = await ATTrackingManager.requestTrackingAuthorization()
        }
    }

    extension PermissionStatus {
        init(_ status: ATTrackingManager.AuthorizationStatus) {
            switch status {
            case .notDetermined: self = .notDetermined
            case .restricted: self = .restricted
            case .denied: self = .denied
            case .authorized: self = .authorized
            @unknown default: self = .unknown(rawValue: Int(status.rawValue))
            }
        }
    }
#endif
