#if DEBUG
    /// A permission the app declares, with the usage descriptions its Info.plist gives for it.
    struct DeclaredPermission: Identifiable, Hashable, Sendable {
        let kind: PermissionKind
        /// The declaring keys found, in the order of `kind.keys`, each with its description.
        /// Empty for notifications, which need none.
        let usageDescriptions: [UsageDescription]

        var id: PermissionKind {
            kind
        }

        /// Whether the Info.plist declares `key` for it.
        func declares(_ key: String) -> Bool {
            usageDescriptions.contains { $0.key == key }
        }

        /// The permissions `infoDictionary` declares, in the drawer's order: each recognized kind
        /// with a non-empty usage description, notifications always (they need none), then
        /// every other `NS…UsageDescription` key, sorted.
        ///
        /// - Parameter infoDictionary: An Info.plist's contents, as `Bundle.infoDictionary` has them.
        static func declared(in infoDictionary: [String: Any]) -> [DeclaredPermission] {
            // Only the usage descriptions, filtered by name first: an app's Info.plist holds
            // hundreds of other keys.
            let descriptions = [String: String](uniqueKeysWithValues: infoDictionary.compactMap { key, value -> (String, String)? in
                guard key.hasSuffix("UsageDescription"), let text = value as? String, !text.isEmpty else { return nil }
                return (key, text)
            })
            let recognized = PermissionKind.recognized.compactMap { kind -> DeclaredPermission? in
                let found = kind.keys.compactMap { key in descriptions[key].map { UsageDescription(key: key, text: $0) } }
                guard !found.isEmpty || kind == .notifications else { return nil }
                return DeclaredPermission(kind: kind, usageDescriptions: found)
            }
            let unrecognized = descriptions.keys.sorted().compactMap { key -> DeclaredPermission? in
                guard case .unrecognized = PermissionKind(usageDescriptionKey: key), let text = descriptions[key] else { return nil }
                return DeclaredPermission(kind: .unrecognized(key: key), usageDescriptions: [UsageDescription(key: key, text: text)])
            }
            return recognized + unrecognized
        }
    }

    /// An Info.plist key and the reason it gives the user.
    struct UsageDescription: Hashable, Sendable {
        let key: String
        let text: String
    }
#endif
