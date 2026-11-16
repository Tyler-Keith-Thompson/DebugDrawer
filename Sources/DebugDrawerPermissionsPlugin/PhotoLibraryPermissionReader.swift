#if DEBUG
    import Photos

    /// The photo library, read-write or add-only, through Photos.
    struct PhotoLibraryPermissionReader: SystemPermissionReader {
        let accessLevel: PHAccessLevel

        static var readWrite: Self {
            Self(accessLevel: .readWrite)
        }

        static var addOnly: Self {
            Self(accessLevel: .addOnly)
        }

        func status(of _: DeclaredPermission) async -> PermissionStatus {
            PermissionStatus(PHPhotoLibrary.authorizationStatus(for: accessLevel))
        }

        func request(_: DeclaredPermission) async {
            _ = await PHPhotoLibrary.requestAuthorization(for: accessLevel)
        }
    }

    extension PermissionStatus {
        init(_ status: PHAuthorizationStatus) {
            switch status {
            case .notDetermined: self = .notDetermined
            case .restricted: self = .restricted
            case .denied: self = .denied
            case .authorized: self = .authorized
            case .limited: self = .limited
            @unknown default: self = .unknown(rawValue: status.rawValue)
            }
        }
    }
#endif
