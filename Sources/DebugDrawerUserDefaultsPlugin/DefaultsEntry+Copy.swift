#if DEBUG
    import DebugDrawer
    import Foundation

    // Copy Value's text, apart from the entry: copying is the view's (and the report's), and a
    // reader elsewhere copies to its own clipboard from the snapshot's values.

    extension DefaultsEntry {
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
