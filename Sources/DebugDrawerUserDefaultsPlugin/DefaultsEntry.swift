#if DEBUG
    import DebugDrawer
    import Foundation

    /// A key of a suite, its value, and the domain the value comes from.
    struct DefaultsEntry: Identifiable, Equatable {
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

        /// What Copy Value puts on the clipboard: the value as text, or the mask when the key
        /// contains a key pattern.
        func copiedValue(redaction: DebugDrawerRedaction) -> String {
            redaction.redacting(value.copiedText, forKey: key)
        }
    }

    extension PropertyListValue {
        /// The value as text to paste: a scalar as the editor shows it, data in hex, and an array
        /// or a dictionary in the old-style property list Foundation describes it in.
        var copiedText: String {
            switch self {
            case let .data(data): DataTextEncoding.hex.text(for: data)
            case .array, .dictionary: String(describing: propertyList as AnyObject)
            case .string, .number, .bool, .date: summary
            }
        }
    }
#endif
