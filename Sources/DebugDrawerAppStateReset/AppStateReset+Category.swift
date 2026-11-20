import Foundation

extension AppStateReset {
    /// A kind of state a reset clears, each one a checkbox of its own.
    public enum Category: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
        /// The keys of the app's UserDefaults domain and of each app group's suite, less
        /// DebugDrawer's own.
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
        /// The cleanup of the app's own, ``AppStateReset/Cleanup``.
        case appCleanup

        /// The category itself.
        public var id: Self {
            self
        }

        /// The category's name, as the drawer and a sidecar list it ("URL cache").
        public var title: String {
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

        /// The SF Symbol a list shows beside it.
        public var systemImage: String {
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
        package var noun: String? {
            switch self {
            case .userDefaults: "key"
            case .keychain, .files, .caches: "item"
            case .cookies: "cookie"
            case .urlCache, .appCleanup: nil
            }
        }

        /// The order a reset runs in. The app's cleanup goes first, so it can close a database
        /// before its file is deleted, and the URL cache before Caches, which holds its store.
        package static let resetOrder: [Self] = [.appCleanup, .keychain, .userDefaults, .cookies, .urlCache, .caches, .files]
    }
}

// The keychain is never among `.all`: it holds the app's credentials, and clearing it signs the
// employee out of everything, so a host allows it on its own, by name
// (`AppStateResetRequests(sessions:allowing:allowingKeychain:...)`), rather than as one member of a
// set it may write as "everything".
extension Set<AppStateReset.Category> {
    /// Every category but the keychain, which a host allows only on its own: UserDefaults, files,
    /// caches, cookies, the URL cache and the app's cleanup (offered only when the host supplies
    /// one).
    public static var all: Self {
        Set(AppStateReset.Category.allCases.filter { $0 != .keychain })
    }
}
