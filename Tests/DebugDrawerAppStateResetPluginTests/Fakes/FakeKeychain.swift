#if DEBUG
    import Foundation
    import Security
    @testable import DebugDrawerAppStateResetPlugin

    /// A keychain in memory that can refuse to be read, or to delete chosen items.
    @MainActor
    final class FakeKeychain: Keychain {
        var stored: [KeychainItem]
        /// What reading the keychain throws; `nil` to read it.
        var readError: KeychainError?
        /// Items, by persistent reference, whose deletion fails with a status.
        var refusals: [Data: OSStatus] = [:]
        private(set) var deleted: [KeychainItem] = []

        init(_ stored: [KeychainItem] = []) {
            self.stored = stored
        }

        func items() throws(KeychainError) -> [KeychainItem] {
            if let readError { throw readError }
            return stored
        }

        func delete(_ item: KeychainItem) throws(KeychainError) {
            if let status = refusals[item.persistentReference] { throw KeychainError(status: status) }
            stored.removeAll { $0 == item }
            deleted.append(item)
        }

        /// A generic password whose persistent reference is its service and account.
        static func password(service: String, account: String) -> KeychainItem {
            KeychainItem(
                itemClass: .genericPassword, service: service, account: account, label: nil,
                persistentReference: Data("\(service)/\(account)".utf8)
            )
        }
    }
#endif
