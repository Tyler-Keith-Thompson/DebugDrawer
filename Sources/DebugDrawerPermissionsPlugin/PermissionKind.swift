#if DEBUG
    /// A privacy permission an app asks the user for, and the Info.plist keys that declare why.
    enum PermissionKind: Hashable, Sendable {
        case camera
        case microphone
        /// Reading and adding to the photo library.
        case photoLibrary
        /// Adding to the photo library only.
        case photoLibraryAdd
        case location
        case contacts
        case calendars
        case reminders
        /// Needs no usage description: every app may ask.
        case notifications
        /// App Tracking Transparency.
        case tracking
        /// Motion and fitness activity (iOS).
        case motion
        case speechRecognition
        case bluetooth
        /// Has no status API: the system tells the app nothing about it.
        case localNetwork
        /// The media library and Apple Music (iOS).
        case mediaLibrary
        /// A usage description the plugin has no status reader for (`NSFaceIDUsageDescription`,
        /// `NSHealthShareUsageDescription`), listed so every declared permission shows.
        case unrecognized(key: String)

        /// Every kind the plugin reads, in the order the drawer lists them.
        static let recognized: [PermissionKind] = [
            .camera, .microphone, .photoLibrary, .photoLibraryAdd, .location, .contacts, .calendars, .reminders,
            .notifications, .tracking, .motion, .speechRecognition, .bluetooth, .localNetwork, .mediaLibrary
        ]

        /// The Info.plist keys whose usage description declares it, the current one first.
        /// Notifications have none.
        var keys: [String] {
            switch self {
            case .camera: ["NSCameraUsageDescription"]
            case .microphone: ["NSMicrophoneUsageDescription"]
            case .photoLibrary: ["NSPhotoLibraryUsageDescription"]
            case .photoLibraryAdd: ["NSPhotoLibraryAddUsageDescription"]
            case .location:
                [
                    "NSLocationWhenInUseUsageDescription", "NSLocationAlwaysAndWhenInUseUsageDescription",
                    "NSLocationAlwaysUsageDescription", "NSLocationUsageDescription"
                ]
            case .contacts: ["NSContactsUsageDescription"]
            case .calendars:
                ["NSCalendarsFullAccessUsageDescription", "NSCalendarsWriteOnlyAccessUsageDescription", "NSCalendarsUsageDescription"]
            case .reminders: ["NSRemindersFullAccessUsageDescription", "NSRemindersUsageDescription"]
            case .notifications: []
            case .tracking: ["NSUserTrackingUsageDescription"]
            case .motion: ["NSMotionUsageDescription"]
            case .speechRecognition: ["NSSpeechRecognitionUsageDescription"]
            case .bluetooth: ["NSBluetoothAlwaysUsageDescription", "NSBluetoothPeripheralUsageDescription"]
            case .localNetwork: ["NSLocalNetworkUsageDescription"]
            case .mediaLibrary: ["NSAppleMusicUsageDescription"]
            case let .unrecognized(key): [key]
            }
        }

        var title: String {
            switch self {
            case .camera: "Camera"
            case .microphone: "Microphone"
            case .photoLibrary: "Photos"
            case .photoLibraryAdd: "Photos (Add Only)"
            case .location: "Location"
            case .contacts: "Contacts"
            case .calendars: "Calendars"
            case .reminders: "Reminders"
            case .notifications: "Notifications"
            case .tracking: "Tracking"
            case .motion: "Motion & Fitness"
            case .speechRecognition: "Speech Recognition"
            case .bluetooth: "Bluetooth"
            case .localNetwork: "Local Network"
            case .mediaLibrary: "Media & Apple Music"
            case let .unrecognized(key): key
            }
        }

        /// An SF Symbol for the permission.
        var icon: String {
            switch self {
            case .camera: "camera"
            case .microphone: "mic"
            case .photoLibrary: "photo.on.rectangle"
            case .photoLibraryAdd: "photo.badge.plus"
            case .location: "location"
            case .contacts: "person.crop.circle"
            case .calendars: "calendar"
            case .reminders: "checklist"
            case .notifications: "bell"
            case .tracking: "hand.raised"
            case .motion: "figure.walk"
            case .speechRecognition: "waveform"
            case .bluetooth: "dot.radiowaves.left.and.right"
            case .localNetwork: "network"
            case .mediaLibrary: "music.note"
            case .unrecognized: "lock.shield"
            }
        }

        /// Whether this platform has an API that reads it: Motion and the media library are
        /// iOS's alone.
        var existsOnThisPlatform: Bool {
            switch self {
            case .motion, .mediaLibrary:
                #if os(iOS)
                    true
                #else
                    false
                #endif
            default:
                true
            }
        }
    }

    extension PermissionKind {
        /// The kind a usage-description key declares, or nil for a key that isn't one.
        init?(usageDescriptionKey key: String) {
            if let kind = Self.recognized.first(where: { $0.keys.contains(key) }) {
                self = kind
            } else if key.hasPrefix("NS"), key.hasSuffix("UsageDescription") {
                self = .unrecognized(key: key)
            } else {
                return nil
            }
        }
    }
#endif
