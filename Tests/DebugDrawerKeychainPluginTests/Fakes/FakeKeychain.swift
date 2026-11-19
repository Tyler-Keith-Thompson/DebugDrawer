#if DEBUG
    @testable import DebugDrawerKeychainPlugin
    import Foundation
    import Security

    /// A keychain in memory that behaves as the data protection keychain does for the calls the
    /// plugin makes: items found by persistent reference, an added password put in the default
    /// group unless it names one, a duplicate service and account in a group refused, dates
    /// stamped from `now`. It can refuse to be read, and it counts the reads of each item's value.
    @MainActor
    final class FakeKeychain: Keychain {
        /// One stored item: its class, its attributes as `SecItemCopyMatching` returns them, and
        /// its value.
        struct Record {
            let itemClass: KeychainItemClass
            let reference: Data
            var attributes: [String: Any]
            var value: Data?
        }

        private(set) var records: [Record] = []
        /// The group an added password goes in when it names none.
        let defaultGroup: String
        /// What every call throws; `nil` to answer.
        var refusal: KeychainError?
        /// The time added and modified items are stamped with.
        var now: Date
        /// The persistent references whose value has been read.
        private(set) var valueReads: [Data] = []
        /// What a delete of the item with each persistent reference throws, the rest answering.
        var deleteRefusals: [Data: KeychainError] = [:]
        /// Whether listing returns the items in the order they were stored, every class mixed, as a
        /// keychain that doesn't group them would; by class otherwise, as the real one is asked.
        var listsInStoredOrder = false
        /// Every call the plugin made, in order.
        private(set) var calls: [Call] = []
        private var nextReference = 0

        /// A call the plugin made, by what it named.
        enum Call: Equatable {
            case items
            case value(Data)
            case add(GenericPassword)
            case update(Data, GenericPassword)
            case delete(Data)
        }

        init(defaultGroup: String = "TEAMID.com.example.app", now: Date = Date(timeIntervalSinceReferenceDate: 800_000_000)) {
            self.defaultGroup = defaultGroup
            self.now = now
        }

        /// Stores an item of `itemClass` with `attributes`, as another part of the app would add it.
        @discardableResult
        func seed(_ itemClass: KeychainItemClass, _ attributes: [String: Any], value: Data? = nil) -> Data {
            let reference = makeReference()
            var stored = attributes
            stored[kSecAttrAccessGroup as String] = stored[kSecAttrAccessGroup as String] ?? defaultGroup
            records.append(Record(itemClass: itemClass, reference: reference, attributes: stored, value: value))
            return reference
        }

        func items() throws(KeychainError) -> [KeychainItem] {
            calls.append(.items)
            if let refusal { throw refusal }
            let listed = listsInStoredOrder
                ? records
                : KeychainItemClass.allCases.flatMap { itemClass in records.filter { $0.itemClass == itemClass } }
            return listed.compactMap { record in
                var result = record.attributes
                result[kSecClass as String] = record.itemClass.secClass as String
                result[kSecValuePersistentRef as String] = record.reference
                return KeychainItem(itemClass: record.itemClass, result: result)
            }
        }

        func value(of item: KeychainItem) throws(KeychainError) -> Data? {
            calls.append(.value(item.persistentReference))
            if let refusal { throw refusal }
            valueReads.append(item.persistentReference)
            guard let record = records.first(where: { $0.reference == item.persistentReference }) else {
                throw KeychainError(status: errSecItemNotFound)
            }
            return item.itemClass.holdsPassword ? record.value : nil
        }

        func add(_ password: GenericPassword) throws(KeychainError) {
            calls.append(.add(password))
            if let refusal { throw refusal }
            let group = password.accessGroup ?? defaultGroup
            let duplicate = records.contains {
                $0.itemClass == .genericPassword && $0.attributes[kSecAttrAccessGroup as String] as? String == group
                    && $0.attributes[kSecAttrService as String] as? String == password.service
                    && $0.attributes[kSecAttrAccount as String] as? String == password.account
            }
            if duplicate { throw KeychainError(status: errSecDuplicateItem) }
            var attributes = Self.attributes(of: password)
            attributes[kSecAttrAccessGroup as String] = group
            attributes[kSecAttrSynchronizable as String] = NSNumber(value: 0)
            attributes[kSecAttrCreationDate as String] = now
            attributes[kSecAttrModificationDate as String] = now
            records.append(Record(itemClass: .genericPassword, reference: makeReference(), attributes: attributes, value: Data(password.value.utf8)))
        }

        func update(_ item: KeychainItem, to password: GenericPassword) throws(KeychainError) {
            calls.append(.update(item.persistentReference, password))
            if let refusal { throw refusal }
            guard let index = records.firstIndex(where: { $0.reference == item.persistentReference }) else {
                throw KeychainError(status: errSecItemNotFound)
            }
            records[index].attributes.merge(Self.attributes(of: password)) { _, new in new }
            records[index].attributes[kSecAttrModificationDate as String] = now
            records[index].value = Data(password.value.utf8)
        }

        func delete(_ item: KeychainItem) throws(KeychainError) {
            calls.append(.delete(item.persistentReference))
            if let refusal { throw refusal }
            if let refused = deleteRefusals[item.persistentReference] { throw refused }
            records.removeAll { $0.reference == item.persistentReference }
        }

        private static func attributes(of password: GenericPassword) -> [String: Any] {
            [
                kSecAttrService as String: password.service,
                kSecAttrAccount as String: password.account,
                kSecAttrLabel as String: password.label,
                kSecAttrAccessible as String: password.accessibility.secValue as String
            ]
        }

        private func makeReference() -> Data {
            nextReference += 1
            return Data("reference-\(nextReference)".utf8)
        }
    }
#endif
