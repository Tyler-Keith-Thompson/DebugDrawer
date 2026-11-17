#if DEBUG
    import Foundation

    /// One entitlement: its key, and its value as text.
    struct Entitlement: Equatable {
        /// A value as App Info shows it.
        enum Value: Equatable {
            /// A switch, such as `com.apple.security.app-sandbox`.
            case boolean(Bool)
            /// A string, or the items of an array, such as each associated domain; a dictionary's
            /// entries as `key = value`.
            case list([String])
        }

        var key: String
        var value: Value

        /// A word label for a common key ("Associated domains"); the key itself for the rest.
        var label: String {
            Self.wordLabels.first { $0.key == key }?.label ?? key
        }

        /// The value on one line, for Copy Info and the bug report.
        var text: String {
            switch value {
            case let .boolean(isOn): isOn ? "Yes" : "No"
            case let .list(items): items.joined(separator: ", ")
            }
        }

        // In display order: associated domains first, since a universal link that won't open is
        // the question most often brought here.
        static let wordLabels: [(key: String, label: String)] = [
            ("com.apple.developer.associated-domains", "Associated domains"),
            ("com.apple.security.application-groups", "App groups"),
            ("keychain-access-groups", "Keychain access groups"),
            ("com.apple.security.app-sandbox", "App sandbox"),
            ("get-task-allow", "Get task allow"),
            ("com.apple.security.get-task-allow", "Get task allow"),
            ("application-identifier", "App ID"),
            ("com.apple.application-identifier", "App ID"),
            ("com.apple.developer.team-identifier", "Team ID"),
            ("aps-environment", "Push environment"),
            ("com.apple.developer.aps-environment", "Push environment"),
            ("com.apple.developer.icloud-container-identifiers", "iCloud containers"),
            ("com.apple.developer.ubiquity-kvstore-identifier", "iCloud key-value store"),
            ("com.apple.developer.applesignin", "Sign in with Apple"),
            ("com.apple.security.network.client", "Outgoing connections"),
            ("com.apple.security.network.server", "Incoming connections"),
            ("com.apple.security.files.user-selected.read-write", "User-selected files")
        ]
    }

    extension Entitlement {
        /// Whether this entitlement is listed before `other`: one with a word label before one
        /// without, in the labels' order, then by key.
        func precedes(_ other: Entitlement) -> Bool {
            let rank = Self.wordLabels.firstIndex { $0.key == key } ?? Self.wordLabels.count
            let otherRank = Self.wordLabels.firstIndex { $0.key == other.key } ?? Self.wordLabels.count
            return rank == otherRank ? key < other.key : rank < otherRank
        }
    }

    extension Entitlement.Value {
        /// The value of a property list object.
        init(_ object: Any) {
            if let isOn = Self.boolean(object) {
                self = .boolean(isOn)
            } else if let array = object as? [Any] {
                self = .list(array.map(Self.text))
            } else if let dictionary = object as? [String: Any] {
                self = .list(dictionary.sorted { $0.key < $1.key }.map { "\($0.key) = \(Self.text($0.value))" })
            } else {
                self = .list([Self.text(object)])
            }
        }

        /// A property list `<true/>` or `<false/>`; nil for a number, which bridges to `Bool` too.
        private static func boolean(_ object: Any) -> Bool? {
            let reference = object as AnyObject
            guard CFGetTypeID(reference) == CFBooleanGetTypeID() else { return nil }
            return object as? Bool
        }

        private static func text(_ object: Any) -> String {
            if let isOn = boolean(object) { return isOn ? "Yes" : "No" }
            if let string = object as? String { return string }
            return "\(object)"
        }
    }
#endif
