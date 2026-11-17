#if DEBUG
    import Foundation

    /// An activity the plugin continues: a universal link, or an activity of the app's own type
    /// with its userInfo.
    struct DeepLinkActivity: Hashable, Codable, Sendable {
        /// `NSUserActivityTypeBrowsingWeb` for a universal link; otherwise the app's own type
        /// ("com.example.app.viewOrder").
        var activityType: String
        /// The link a universal link opens; `nil` for an activity of the app's own type.
        var webpageURL: URL?
        /// The userInfo, in the order the form lists it.
        var userInfo: [UserInfoEntry]

        /// A universal link to `url`, as the system hands one to the app when the user taps it.
        static func universalLink(_ url: URL) -> Self {
            Self(activityType: NSUserActivityTypeBrowsingWeb, webpageURL: url, userInfo: [])
        }

        /// Whether this is a universal link rather than an activity of the app's own type.
        var isUniversalLink: Bool {
            activityType == NSUserActivityTypeBrowsingWeb
        }

        /// The activity the app's continuation path receives.
        ///
        /// A universal link's `webpageURL` must be http or https: `NSUserActivity` raises an
        /// exception on any other scheme, so the form offers Continue for those alone.
        func makeUserActivity() -> NSUserActivity {
            let activity = NSUserActivity(activityType: activityType)
            activity.webpageURL = webpageURL
            if !userInfo.isEmpty {
                // The form refuses repeated keys, so the last one winning never drops a value.
                activity.userInfo = Dictionary(userInfo.map { ($0.key, $0.value.propertyListObject) }) { $1 }
            }
            return activity
        }
    }

    extension URL {
        /// Whether a universal link can carry the URL: an http or https URL with a host.
        var isWebURL: Bool {
            ["http", "https"].contains(scheme?.lowercased()) && host?.isEmpty == false
        }
    }
#endif
