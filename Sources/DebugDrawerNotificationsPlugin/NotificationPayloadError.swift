#if DEBUG
    /// Why pasted text isn't an APNs payload the drawer can send.
    enum NotificationPayloadError: Error, Equatable, Sendable {
        /// Nothing but whitespace.
        case empty
        /// Not valid JSON.
        case notJSON
        /// JSON, but not an object.
        case notAnObject
        /// An object without the `aps` key every push carries.
        case missingAPS
        /// `key`'s value isn't what APNs takes there.
        case wrongType(key: String, expected: String)

        /// What the drawer shows under the editor.
        var message: String {
            switch self {
            case .empty: "Paste an APNs payload: a JSON object with an aps dictionary."
            case .notJSON: "This isn’t valid JSON."
            case .notAnObject: "The payload must be a JSON object."
            case .missingAPS: "The payload has no aps dictionary."
            case let .wrongType(key, expected): "\(key) must be \(expected)."
            }
        }
    }
#endif
