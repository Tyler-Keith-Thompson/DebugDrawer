#if DEBUG
    @testable import DebugDrawerDeepLinkPlugin
    import Foundation
    import Testing

    // Each test keeps its history in a suite of its own, named with a UUID, and removes its
    // persistent domain afterwards.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct DeepLinkModelTests {
        @Test("Continuing an https URL hands the registered handler a browsing-web activity with that webpageURL")
        func universalLinkReachesHandler() throws {
            let name = "DebugDrawerTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: name))
            defer { defaults.removePersistentDomain(forName: name) }
            var received: [NSUserActivity] = []
            let sut = DeepLinkModel(delivery: _UserActivityDelivering(handler: { received.append($0) }), defaults: defaults)
            let url = try #require(URL(string: "https://example.com/orders/42?ref=mail"))
            let expectedType = NSUserActivityTypeBrowsingWeb

            sut.continue(.universalLink(url))

            let actual = try #require(received.first)
            #expect(received.count == 1)
            #expect(actual.activityType == expectedType)
            #expect(actual.webpageURL == url)
            #expect(sut.outcome == .continued(.handler))
        }

        @Test("An activity of the app's own type reaches the handler with its type and every userInfo value intact")
        func customActivityReachesHandler() throws {
            let name = "DebugDrawerTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: name))
            defer { defaults.removePersistentDomain(forName: name) }
            var received: [NSUserActivity] = []
            let sut = DeepLinkModel(delivery: _UserActivityDelivering(handler: { received.append($0) }), defaults: defaults)
            let activity = DeepLinkActivity(
                activityType: "com.example.app.viewOrder",
                webpageURL: nil,
                userInfo: [
                    UserInfoEntry(key: "orderID", value: .integer(42)),
                    UserInfoEntry(key: "total", value: .double(9.5)),
                    UserInfoEntry(key: "title", value: .string("Ada's order")),
                    UserInfoEntry(key: "gift", value: .bool(true))
                ]
            )
            let expectedType = "com.example.app.viewOrder"
            let expectedKeys: Set<String> = ["orderID", "total", "title", "gift"]
            let expectedOrderID = 42
            let expectedTotal = 9.5
            let expectedTitle = "Ada's order"

            sut.continue(activity)

            let actual = try #require(received.first)
            let userInfo = try #require(actual.userInfo)
            #expect(actual.activityType == expectedType)
            #expect(actual.webpageURL == nil)
            #expect(Set(userInfo.keys.compactMap { $0 as? String }) == expectedKeys)
            #expect(userInfo["orderID"] as? Int == expectedOrderID)
            #expect(userInfo["total"] as? Double == expectedTotal)
            #expect(userInfo["title"] as? String == expectedTitle)
            #expect(userInfo["gift"] as? Bool == true)
        }

        @Test("An activity with no userInfo arrives with none")
        func emptyUserInfo() throws {
            let name = "DebugDrawerTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: name))
            defer { defaults.removePersistentDomain(forName: name) }
            let delivery = FakeUserActivityDelivering()
            let sut = DeepLinkModel(delivery: delivery, defaults: defaults)

            sut.continue(DeepLinkActivity(activityType: "com.example.app.compose", webpageURL: nil, userInfo: []))

            let actual = try #require(delivery.delivered.first)
            #expect(actual.userInfo?.isEmpty ?? true)
        }

        @Test("With no handler and no delegate method, the outcome tells the developer to pass continueUserActivity:")
        func unhandledOutcome() throws {
            let name = "DebugDrawerTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: name))
            defer { defaults.removePersistentDomain(forName: name) }
            let sut = DeepLinkModel(delivery: FakeUserActivityDelivering(answer: .unhandled), defaults: defaults)
            let url = try #require(URL(string: "https://example.com/path"))
            let expected = "This app has no handler: pass continueUserActivity: to installDeepLink"

            sut.continue(.universalLink(url))

            let actual = try #require(sut.outcome)
            #expect(actual.text == expected)
            #expect(actual.severity == .error)
        }

        @Test("Continued activities are listed most recent first, once each, apart from the URLs opened")
        func activityHistory() throws {
            let name = "DebugDrawerTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: name))
            defer { defaults.removePersistentDomain(forName: name) }
            let sut = DeepLinkModel(delivery: FakeUserActivityDelivering(), defaults: defaults)
            let first = try DeepLinkActivity.universalLink(#require(URL(string: "https://example.com/a")))
            let second = DeepLinkActivity(
                activityType: "com.example.app.viewOrder", webpageURL: nil, userInfo: [UserInfoEntry(key: "orderID", value: .integer(7))]
            )
            let expected = [first, second]

            sut.continue(first)
            sut.continue(second)
            sut.continue(first)

            #expect(sut.activities == expected)
            #expect(sut.history.isEmpty)
        }

        @Test("The activity history is kept 30 deep and read back by the next model on the same defaults")
        func activityHistoryPersists() throws {
            let name = "DebugDrawerTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: name))
            defer { defaults.removePersistentDomain(forName: name) }
            let sut = DeepLinkModel(delivery: FakeUserActivityDelivering(), defaults: defaults)
            let activities = (0 ..< 31).map {
                DeepLinkActivity(activityType: "com.example.app.item", webpageURL: nil, userInfo: [UserInfoEntry(key: "index", value: .integer($0))])
            }
            let expected = Array(activities.reversed().prefix(30))

            activities.forEach { sut.continue($0) }

            let actual = DeepLinkModel(delivery: FakeUserActivityDelivering(), defaults: defaults).activities
            #expect(actual == expected)
        }

        @Test("Clear History empties both the URLs and the activities, here and in the defaults")
        func clearHistory() throws {
            let name = "DebugDrawerTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: name))
            defer { defaults.removePersistentDomain(forName: name) }
            defaults.set(["myapp://orders/42"], forKey: DeepLinkModel.historyKey)
            let sut = DeepLinkModel(delivery: FakeUserActivityDelivering(), defaults: defaults)
            sut.continue(try .universalLink(#require(URL(string: "https://example.com/a"))))

            sut.clearHistory()

            let reread = DeepLinkModel(delivery: FakeUserActivityDelivering(), defaults: defaults)
            #expect(sut.history.isEmpty)
            #expect(sut.activities.isEmpty)
            #expect(reread.history.isEmpty)
            #expect(reread.activities.isEmpty)
        }
    }
#endif
