#if DEBUG
    import Foundation

    /// The history kept in a defaults suite: the drawer's own, apart from the app's defaults. The
    /// URLs are a string array and the activities JSON, each under a key of its own; an empty list
    /// removes its key.
    struct _DeepLinkHistoryStore: DeepLinkHistoryStore {
        static let historyKey = "com.debugdrawer.deeplink.history"
        static let activitiesKey = "com.debugdrawer.deeplink.activities"

        let defaults: UserDefaults

        func load() -> DeepLinkHistory {
            DeepLinkHistory(
                urls: defaults.stringArray(forKey: Self.historyKey) ?? [],
                // Activities written by another version that no longer decode start empty.
                activities: defaults.data(forKey: Self.activitiesKey)
                    .flatMap { try? JSONDecoder().decode([DeepLinkActivity].self, from: $0) } ?? []
            )
        }

        func save(_ history: DeepLinkHistory) {
            if history.urls.isEmpty {
                defaults.removeObject(forKey: Self.historyKey)
            } else {
                defaults.set(history.urls, forKey: Self.historyKey)
            }
            // Encoding strings, numbers and Booleans can't fail.
            if history.activities.isEmpty {
                defaults.removeObject(forKey: Self.activitiesKey)
            } else if let data = try? JSONEncoder().encode(history.activities) {
                defaults.set(data, forKey: Self.activitiesKey)
            }
        }
    }
#endif
