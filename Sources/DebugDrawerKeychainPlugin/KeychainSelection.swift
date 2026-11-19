#if DEBUG
    import Foundation

    // Deliberately not `Codable`: it holds a password, which stays in the app's process. The
    // snapshot carries `KeychainOpenItem` in its place.

    /// The item whose detail is open, with its password as read when it was opened.
    struct KeychainSelection: Hashable, Sendable {
        let item: KeychainItem
        /// The password; `nil` for an item that holds none, or a failure to read it.
        let value: Result<Data?, KeychainError>
    }
#endif
