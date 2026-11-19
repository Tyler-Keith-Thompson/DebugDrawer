#if DEBUG
    @testable import DebugDrawerDeepLinkPlugin
    import Foundation
    import Testing

    // Each test keeps its history in a defaults suite of its own, named with a UUID, and removes its
    // persistent domain afterwards.
    @MainActor
    @Suite
    struct DeepLinkHistoryStoreTests {
        @Test("A saved history is read back by another store on the same defaults, the URLs as a string array")
        func savesAndLoads() throws {
            let name = "DeepLinkHistoryStoreTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: name))
            defer { defaults.removePersistentDomain(forName: name) }
            let sut = _DeepLinkHistoryStore(defaults: defaults)
            let expected = DeepLinkHistory(
                urls: ["myapp://b", "myapp://a"],
                activities: [DeepLinkActivity(
                    activityType: "com.example.app.viewOrder", webpageURL: nil, userInfo: [UserInfoEntry(key: "orderID", value: .integer(7))]
                )]
            )

            sut.save(expected)

            let actual = _DeepLinkHistoryStore(defaults: defaults).load()
            #expect(actual == expected)
            #expect(defaults.stringArray(forKey: _DeepLinkHistoryStore.historyKey) == expected.urls)
        }

        @Test("Saving an empty history removes both keys")
        func emptyRemovesKeys() throws {
            let name = "DeepLinkHistoryStoreTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: name))
            defer { defaults.removePersistentDomain(forName: name) }
            let sut = _DeepLinkHistoryStore(defaults: defaults)
            try sut.save(DeepLinkHistory(urls: ["myapp://a"], activities: [.universalLink(#require(URL(string: "https://example.com/a")))]))

            sut.save(DeepLinkHistory())

            #expect(defaults.object(forKey: _DeepLinkHistoryStore.historyKey) == nil)
            #expect(defaults.object(forKey: _DeepLinkHistoryStore.activitiesKey) == nil)
            #expect(sut.load() == DeepLinkHistory())
        }

        @Test("Activities that no longer decode start empty, and the URLs are still read")
        func undecodableActivities() throws {
            let name = "DeepLinkHistoryStoreTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: name))
            defer { defaults.removePersistentDomain(forName: name) }
            defaults.set(["myapp://a"], forKey: _DeepLinkHistoryStore.historyKey)
            defaults.set(Data("not json".utf8), forKey: _DeepLinkHistoryStore.activitiesKey)
            let sut = _DeepLinkHistoryStore(defaults: defaults)
            let expected = DeepLinkHistory(urls: ["myapp://a"], activities: [])

            let actual = sut.load()

            #expect(actual == expected)
        }
    }
#endif
