#if DEBUG
    import Foundation

    /// What the app has reported of its registration for remote notifications.
    enum RemoteRegistration: Equatable, Sendable {
        /// Nothing reported yet: the app hasn't registered, or doesn't forward the token.
        case notRegistered
        /// APNs gave the app this device token.
        case registered(deviceToken: Data)
        /// Registering failed, for this reason.
        case failed(message: String)

        /// What the bug report and the drawer's rules redact the token under; the standard rules
        /// mask any key containing `token`.
        static let redactionKey = "deviceToken"
    }

    extension Data {
        /// The bytes as lowercase hexadecimal, two digits each, as push services take a token.
        var hexadecimal: String {
            map { String(format: "%02x", $0) }.joined()
        }
    }
#endif
