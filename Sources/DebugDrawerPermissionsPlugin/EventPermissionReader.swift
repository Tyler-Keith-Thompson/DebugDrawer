#if DEBUG
    import EventKit

    /// Calendars (`event`) or reminders (`reminder`), through EventKit.
    struct EventPermissionReader: SystemPermissionReader {
        let entityType: EKEntityType

        static var calendars: Self {
            Self(entityType: .event)
        }

        static var reminders: Self {
            Self(entityType: .reminder)
        }

        func status(of _: DeclaredPermission) async -> PermissionStatus {
            PermissionStatus(EKEventStore.authorizationStatus(for: entityType))
        }

        /// Asks for full access, or for calendars declared write-only alone, for write-only access.
        func request(_ permission: DeclaredPermission) async {
            let store = EKEventStore()
            if entityType == .reminder {
                _ = try? await store.requestFullAccessToReminders()
            } else if permission.declares("NSCalendarsFullAccessUsageDescription") {
                _ = try? await store.requestFullAccessToEvents()
            } else {
                _ = try? await store.requestWriteOnlyAccessToEvents()
            }
        }
    }

    extension PermissionStatus {
        init(_ status: EKAuthorizationStatus) {
            switch status {
            case .notDetermined: self = .notDetermined
            case .restricted: self = .restricted
            case .denied: self = .denied
            // EventKit's deprecated `authorized` has the same raw value.
            case .fullAccess: self = .authorized
            case .writeOnly: self = .writeOnly
            @unknown default: self = .unknown(rawValue: status.rawValue)
            }
        }
    }
#endif
