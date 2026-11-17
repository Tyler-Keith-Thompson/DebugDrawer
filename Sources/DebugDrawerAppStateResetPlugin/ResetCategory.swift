#if DEBUG
    /// A kind of state the plugin clears, each one a checkbox of its own.
    enum ResetCategory: String, CaseIterable, Hashable, Sendable, Identifiable {
        /// The keys of the app's UserDefaults domain and of each app group's suite.
        case userDefaults
        /// The keychain items the app can read, of every class.
        case keychain
        /// Documents, Application Support and tmp, and each app group's container, but not
        /// Caches, which is a category of its own.
        case files
        /// The contents of Library/Caches, the app's and each app group's.
        case caches
        /// HTTPCookieStorage's cookies, and WebKit's where WebKit exists.
        case cookies
        /// URLCache.shared's responses, on disk and in memory.
        case urlCache
        /// The cleanup the app supplied to `AppStateReset.install(cleanup:)`.
        case appCleanup

        var id: Self {
            self
        }

        /// The category's name in the drawer.
        var title: String {
            switch self {
            case .userDefaults: "UserDefaults"
            case .keychain: "Keychain"
            case .files: "Files"
            case .caches: "Caches"
            case .cookies: "Cookies"
            case .urlCache: "URL cache"
            case .appCleanup: "App cleanup"
            }
        }

        /// The SF Symbol beside it.
        var systemImage: String {
            switch self {
            case .userDefaults: "list.bullet.rectangle"
            case .keychain: "key"
            case .files: "folder"
            case .caches: "internaldrive"
            case .cookies: "doc.plaintext"
            case .urlCache: "network"
            case .appCleanup: "wrench.and.screwdriver"
            }
        }

        /// What the category counts ("key"), `nil` for one that clears as a whole.
        var noun: String? {
            switch self {
            case .userDefaults: "key"
            case .keychain, .files, .caches: "item"
            case .cookies: "cookie"
            case .urlCache, .appCleanup: nil
            }
        }

        /// The order a reset runs in. The app's cleanup goes first, so it can close a database
        /// before its file is deleted, and the URL cache before Caches, which holds its store.
        static let resetOrder: [ResetCategory] = [.appCleanup, .keychain, .userDefaults, .cookies, .urlCache, .caches, .files]
    }
#endif
