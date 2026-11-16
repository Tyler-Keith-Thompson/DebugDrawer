// The media library's authorization exists on iOS alone.
#if DEBUG && os(iOS)
    import MediaPlayer

    /// The media library and Apple Music, through Media Player.
    struct MediaLibraryPermissionReader: SystemPermissionReader {
        func status(of _: DeclaredPermission) async -> PermissionStatus {
            PermissionStatus(MPMediaLibrary.authorizationStatus())
        }

        func request(_: DeclaredPermission) async {
            await withCheckedContinuation { continuation in
                MPMediaLibrary.requestAuthorization { _ in continuation.resume() }
            }
        }
    }

    extension PermissionStatus {
        init(_ status: MPMediaLibraryAuthorizationStatus) {
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
