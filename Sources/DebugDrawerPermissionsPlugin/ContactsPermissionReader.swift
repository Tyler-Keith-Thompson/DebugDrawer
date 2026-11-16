#if DEBUG
    import Contacts

    /// Contacts, through the Contacts framework.
    struct ContactsPermissionReader: SystemPermissionReader {
        func status(of _: DeclaredPermission) async -> PermissionStatus {
            PermissionStatus(CNContactStore.authorizationStatus(for: .contacts))
        }

        func request(_: DeclaredPermission) async {
            _ = try? await CNContactStore().requestAccess(for: .contacts)
        }
    }

    extension PermissionStatus {
        init(_ status: CNAuthorizationStatus) {
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
