#if DEBUG
    /// Reads and requests each permission through the framework that owns it, one reader per
    /// framework.
    ///
    /// It only ever touches a kind the Info.plist declares (notifications need nothing declared),
    /// since asking for one that isn't terminates the app. Each framework is imported in its
    /// reader's file alone, under DEBUG, so a release build references none of them.
    @MainActor
    final class SystemPermissionAuthority: PermissionAuthority {
        private let readers: [PermissionKind: any SystemPermissionReader]

        init() {
            var readers: [PermissionKind: any SystemPermissionReader] = [
                .camera: CapturePermissionReader.camera,
                .microphone: CapturePermissionReader.microphone,
                .photoLibrary: PhotoLibraryPermissionReader.readWrite,
                .photoLibraryAdd: PhotoLibraryPermissionReader.addOnly,
                .location: LocationPermissionReader(),
                .contacts: ContactsPermissionReader(),
                .calendars: EventPermissionReader.calendars,
                .reminders: EventPermissionReader.reminders,
                .notifications: NotificationPermissionReader(),
                .tracking: TrackingPermissionReader(),
                .speechRecognition: SpeechPermissionReader(),
                .bluetooth: BluetoothPermissionReader()
            ]
            #if os(iOS)
                readers[.motion] = MotionPermissionReader()
                readers[.mediaLibrary] = MediaLibraryPermissionReader()
            #endif
            self.readers = readers
        }

        func status(of permission: DeclaredPermission) async -> PermissionStatus {
            guard let reader = readers[permission.kind] else { return permission.unreadableStatus }
            return await reader.status(of: permission)
        }

        func request(_ permission: DeclaredPermission) async {
            await readers[permission.kind]?.request(permission)
        }
    }

    extension DeclaredPermission {
        /// The status of a permission no reader reads: one this platform lacks, local network
        /// (which no API reports), or a usage description the plugin doesn't know.
        fileprivate var unreadableStatus: PermissionStatus {
            if !kind.existsOnThisPlatform {
                .unavailable
            } else if kind == .localNetwork {
                .noStatusAPI
            } else {
                .notChecked
            }
        }
    }
#endif
