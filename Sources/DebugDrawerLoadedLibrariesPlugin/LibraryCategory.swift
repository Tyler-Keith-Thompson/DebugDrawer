#if DEBUG
    /// Whose an image is: the app's own, a third party's, or the system's. The order of the cases
    /// is the order the plugin lists them in.
    enum LibraryCategory: String, CaseIterable, Codable, Sendable {
        case app = "App"
        case thirdParty = "Third-Party"
        case system = "System"
    }
#endif
