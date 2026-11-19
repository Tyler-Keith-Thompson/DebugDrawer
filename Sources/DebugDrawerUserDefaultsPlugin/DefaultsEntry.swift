#if DEBUG
    import Foundation

    /// A key of a suite, its value, and the domain the value comes from.
    struct DefaultsEntry: Codable, Identifiable, Equatable, Sendable {
        let key: String
        let value: PropertyListValue
        /// Where the suite finds the value; only the persistent domain's are edited and deleted.
        let domain: DefaultsDomain

        init(key: String, value: PropertyListValue, domain: DefaultsDomain = .persistent) {
            self.key = key
            self.value = value
            self.domain = domain
        }

        var id: String {
            key
        }
    }
#endif
