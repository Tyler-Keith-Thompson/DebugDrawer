#if DEBUG
    import Foundation

    /// A value in an activity's userInfo: the property-list scalars the form edits.
    enum UserInfoValue: Hashable, Codable, Sendable {
        case string(String)
        case integer(Int)
        case double(Double)
        case bool(Bool)

        /// The object the activity's userInfo holds: a string, or a number that bridges to
        /// `NSNumber`, so the app reads it back with `as? Int`, `as? Double` or `as? Bool`.
        var propertyListObject: Any {
            switch self {
            case let .string(value): value
            case let .integer(value): value
            case let .double(value): value
            case let .bool(value): value
            }
        }

        /// The value as the history shows it: a string quoted, a number or `true`/`false` bare.
        var text: String {
            switch self {
            case let .string(value): "\"\(value)\""
            case let .integer(value): String(value)
            case let .double(value): String(value)
            case let .bool(value): String(value)
            }
        }
    }
#endif
