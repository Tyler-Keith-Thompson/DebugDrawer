#if DEBUG
    import Foundation

    /// What the form sends: a URL opened as the system opens it, a universal link continued in
    /// the app, or an activity of the app's own type continued in the app.
    enum DeepLinkMode: String, CaseIterable, Hashable {
        case open
        case universalLink
        case activity

        var title: String {
            switch self {
            case .open: "Open URL"
            case .universalLink: "Universal Link"
            case .activity: "Activity"
            }
        }

        /// The mode for a typed URL: an http or https URL is continued as a universal link, since
        /// opening one goes to the browser; any other is opened.
        static func suggested(for urlText: String) -> Self {
            URL(string: urlText.trimmingCharacters(in: .whitespaces))?.isWebURL == true ? .universalLink : .open
        }
    }
#endif
