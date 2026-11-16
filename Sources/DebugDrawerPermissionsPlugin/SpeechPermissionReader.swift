#if DEBUG
    import Speech

    /// Speech recognition, through Speech.
    struct SpeechPermissionReader: SystemPermissionReader {
        func status(of _: DeclaredPermission) async -> PermissionStatus {
            PermissionStatus(SFSpeechRecognizer.authorizationStatus())
        }

        func request(_: DeclaredPermission) async {
            await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { _ in continuation.resume() }
            }
        }
    }

    extension PermissionStatus {
        init(_ status: SFSpeechRecognizerAuthorizationStatus) {
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
