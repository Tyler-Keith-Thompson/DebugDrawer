#if DEBUG
    import Foundation
    #if os(iOS)
        import UIKit
    #endif

    extension PermissionKind {
        /// Where Settings shows the permission for this app.
        ///
        /// On iOS, the app's own page in Settings (`openSettingsURLString`), which lists every
        /// permission it declares, or its notification settings
        /// (`openNotificationSettingsURLString`). On macOS, the permission's pane under Privacy &
        /// Security in System Settings, through the `x-apple.systempreferences` URLs: Apple
        /// documents no URL for them, but System Settings has answered these for years and they
        /// are no framework symbol; the plugin exists in debug builds only, so App Review never
        /// sees them. A pane the URL doesn't name opens Privacy & Security itself.
        @MainActor
        var settingsURL: URL? {
            #if os(iOS)
                URL(string: self == .notifications ? UIApplication.openNotificationSettingsURLString : UIApplication.openSettingsURLString)
            #else
                URL(string: macOSSettingsPath)
            #endif
        }

        #if os(macOS)
            private var macOSSettingsPath: String {
                let privacy = "x-apple.systempreferences:com.apple.preference.security?Privacy"
                return switch self {
                case .camera: privacy + "_Camera"
                case .microphone: privacy + "_Microphone"
                case .photoLibrary, .photoLibraryAdd: privacy + "_Photos"
                case .location: privacy + "_LocationServices"
                case .contacts: privacy + "_Contacts"
                case .calendars: privacy + "_Calendars"
                case .reminders: privacy + "_Reminders"
                case .speechRecognition: privacy + "_SpeechRecognition"
                case .bluetooth: privacy + "_Bluetooth"
                case .localNetwork: privacy + "_LocalNetwork"
                case .notifications: "x-apple.systempreferences:com.apple.preference.notifications"
                case .tracking, .motion, .mediaLibrary, .unrecognized: privacy
                }
            }
        #endif
    }
#endif
