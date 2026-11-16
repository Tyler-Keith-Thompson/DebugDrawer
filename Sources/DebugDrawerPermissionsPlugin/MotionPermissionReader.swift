// Core Motion's activity authorization exists on iOS alone.
#if DEBUG && os(iOS)
    import CoreMotion

    /// Motion and fitness activity, through Core Motion. It has no request call: the first
    /// activity query shows the prompt.
    struct MotionPermissionReader: SystemPermissionReader {
        func status(of _: DeclaredPermission) async -> PermissionStatus {
            PermissionStatus(CMMotionActivityManager.authorizationStatus())
        }

        func request(_: DeclaredPermission) async {
            let manager = CMMotionActivityManager()
            await withCheckedContinuation { continuation in
                manager.queryActivityStarting(from: .now.addingTimeInterval(-60), to: .now, to: .main) { _, _ in
                    continuation.resume()
                }
            }
        }
    }

    extension PermissionStatus {
        init(_ status: CMAuthorizationStatus) {
            switch status {
            case .notDetermined: self = .notDetermined
            case .restricted: self = .restricted
            case .denied: self = .denied
            case .authorized: self = .authorized
            @unknown default: self = .unknown(rawValue: status.rawValue)
            }
        }
    }
#endif
