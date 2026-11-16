#if DEBUG
    import AVFoundation

    /// The camera (`video`) or the microphone (`audio`), through AVFoundation.
    struct CapturePermissionReader: SystemPermissionReader {
        let mediaType: AVMediaType

        static var camera: Self {
            Self(mediaType: .video)
        }

        static var microphone: Self {
            Self(mediaType: .audio)
        }

        func status(of _: DeclaredPermission) async -> PermissionStatus {
            PermissionStatus(AVCaptureDevice.authorizationStatus(for: mediaType))
        }

        func request(_: DeclaredPermission) async {
            _ = await AVCaptureDevice.requestAccess(for: mediaType)
        }
    }

    // A case added after the plugin was written is kept as `unknown` with its raw value, here and
    // in every reader, rather than guessed at.
    extension PermissionStatus {
        init(_ status: AVAuthorizationStatus) {
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
