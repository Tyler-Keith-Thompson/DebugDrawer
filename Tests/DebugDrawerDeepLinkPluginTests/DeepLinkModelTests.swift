#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerDeepLinkPlugin
    import Foundation
    import Testing

    // The model is read and driven here as an out-of-process reader would: through its snapshot,
    // encoded and decoded, and commands, sent through a direct transport, with no view. Its opener,
    // continuation path and history store are hand-written fakes; nothing opens a URL or touches
    // the defaults. Opens, continues and clears land a hop after their command, so each test waits
    // on the transport's stream of snapshots for the one it expects.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct DeepLinkModelTests {
        @Test("A snapshot with a typed URL, presets, history, activities and an outcome encodes to JSON and decodes equal")
        func snapshotRoundTrips() async throws {
            let preset = try DeepLinkPreset("Order 42", url: #require(URL(string: "myapp://orders/42")))
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
            let store = FakeDeepLinkHistoryStore(DeepLinkHistory(urls: ["myapp://orders/7"], activities: [activity]))
            let model = DeepLinkModel(
                configuration: DeepLinkConfiguration(presets: [preset], delivery: FakeUserActivityDelivering(answer: .declined), openURL: nil),
                system: FakeSystemURLOpening(),
                store: store
            )
            let transport = DebugDrawerPluginTransport.direct(to: model)
            let snapshots = transport.snapshots()
            transport.send(DeepLinkCommand(.setURLText("myapp://orders/42")))
            transport.send(DeepLinkCommand(.continue(activity)))
            var read: DeepLinkSnapshot?
            for await snapshot in snapshots where snapshot.outcome != nil {
                read = snapshot
                break
            }
            let expected = try #require(read)

            let encoded = try JSONEncoder().encode(expected)
            let actual = try JSONDecoder().decode(DeepLinkSnapshot.self, from: encoded)

            #expect(actual == expected)
            #expect(actual.urlText == "myapp://orders/42")
            #expect(actual.presets == [preset])
            #expect(actual.history == ["myapp://orders/7"])
            #expect(actual.activities == [activity])
            #expect(actual.outcome == .continued(.declined))
        }

        @Test("Every outcome encodes to JSON and decodes equal")
        func outcomesRoundTrip() throws {
            let expected: [DeepLinkOutcome] = [
                .handled("myapp://a"),
                .notHandled("myapp://b"),
                .opened("mailto:test@example.com"),
                .couldNotOpen("nobody://x", reason: "no installed app opens nobody: URLs"),
                .continued(.handler),
                .continued(.sceneDelegate),
                .continued(.applicationDelegate),
                .continued(.declined),
                .continued(.unhandled)
            ]

            let encoded = try JSONEncoder().encode(expected)
            let actual = try JSONDecoder().decode([DeepLinkOutcome].self, from: encoded)

            #expect(actual == expected)
        }

        @Test("A snapshot before anything is sent encodes to JSON and decodes equal, with no outcome")
        func freshSnapshotRoundTrips() throws {
            let sut = DeepLinkModel(
                configuration: DeepLinkConfiguration(presets: [], delivery: FakeUserActivityDelivering(), openURL: nil),
                system: FakeSystemURLOpening(),
                store: FakeDeepLinkHistoryStore()
            )
            let expected = DeepLinkSnapshot()

            let encoded = try JSONEncoder().encode(sut.snapshot)
            let actual = try JSONDecoder().decode(DeepLinkSnapshot.self, from: encoded)

            #expect(actual == expected)
            #expect(actual.outcome == nil)
        }

        @Test("Every command, encoded to JSON and decoded, drives the model through a direct transport")
        func commandsRoundTrip() async throws {
            let system = FakeSystemURLOpening()
            let delivery = FakeUserActivityDelivering()
            let store = FakeDeepLinkHistoryStore()
            let sut = DebugDrawerPluginTransport.direct(to: DeepLinkModel(
                configuration: DeepLinkConfiguration(presets: [], delivery: delivery, openURL: nil), system: system, store: store
            ))
            let snapshots = sut.snapshots()
            let url = try #require(URL(string: "myapp://orders/42"))
            let link = try DeepLinkActivity.universalLink(#require(URL(string: "https://example.com/a")))
            let commands: [DeepLinkCommand] = [
                DeepLinkCommand(.setURLText("myapp://orders/42")),
                DeepLinkCommand(.open(url)),
                DeepLinkCommand(.continue(link)),
                DeepLinkCommand(.clearHistory)
            ]
            let expectedSaves = [
                DeepLinkHistory(urls: ["myapp://orders/42"], activities: []),
                DeepLinkHistory(urls: ["myapp://orders/42"], activities: [link]),
                DeepLinkHistory()
            ]

            for command in commands {
                let decoded = try JSONDecoder().decode(DeepLinkCommand.self, from: JSONEncoder().encode(command))
                #expect(decoded.action == command.action)
                sut.send(decoded)
            }
            for await snapshot in snapshots
                where snapshot.outcome == .continued(.handler) && snapshot.history.isEmpty && snapshot.activities.isEmpty {
                break
            }

            #expect(sut.snapshot.urlText == "myapp://orders/42")
            #expect(system.opened == [url])
            #expect(delivery.delivered.map(\.webpageURL) == [link.webpageURL])
            #expect(store.saved == expectedSaves)
        }

        @Test("Typing changes the URL at once, so a field bound through a direct transport reads back what was typed")
        func typingLandsAtOnce() {
            let sut = DebugDrawerPluginTransport.direct(to: DeepLinkModel(
                configuration: DeepLinkConfiguration(presets: [], delivery: FakeUserActivityDelivering(), openURL: nil),
                system: FakeSystemURLOpening(),
                store: FakeDeepLinkHistoryStore()
            ))
            let expected = "myapp://ord"

            sut.send(DeepLinkCommand(.setURLText(expected)))

            #expect(sut.snapshot.urlText == expected)
        }

        @Test("Continuing an https URL hands the registered handler a browsing-web activity with that webpageURL")
        func universalLinkReachesHandler() async throws {
            var received: [NSUserActivity] = []
            let sut = DebugDrawerPluginTransport.direct(to: DeepLinkModel(
                configuration: DeepLinkConfiguration(presets: [], delivery: _UserActivityDelivering(handler: { received.append($0) }), openURL: nil),
                system: FakeSystemURLOpening(),
                store: FakeDeepLinkHistoryStore()
            ))
            let snapshots = sut.snapshots()
            let url = try #require(URL(string: "https://example.com/orders/42?ref=mail"))
            let expectedType = NSUserActivityTypeBrowsingWeb

            sut.send(DeepLinkCommand(.continue(.universalLink(url))))
            for await snapshot in snapshots where snapshot.outcome != nil {
                break
            }

            let actual = try #require(received.first)
            #expect(received.count == 1)
            #expect(actual.activityType == expectedType)
            #expect(actual.webpageURL == url)
            #expect(sut.snapshot.outcome == .continued(.handler))
        }

        @Test("An activity of the app's own type reaches the handler with its type and every userInfo value intact")
        func customActivityReachesHandler() async throws {
            var received: [NSUserActivity] = []
            let sut = DebugDrawerPluginTransport.direct(to: DeepLinkModel(
                configuration: DeepLinkConfiguration(presets: [], delivery: _UserActivityDelivering(handler: { received.append($0) }), openURL: nil),
                system: FakeSystemURLOpening(),
                store: FakeDeepLinkHistoryStore()
            ))
            let snapshots = sut.snapshots()
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

            sut.send(DeepLinkCommand(.continue(activity)))
            for await snapshot in snapshots where snapshot.outcome != nil {
                break
            }

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
        func emptyUserInfo() async throws {
            let delivery = FakeUserActivityDelivering()
            let sut = DebugDrawerPluginTransport.direct(to: DeepLinkModel(
                configuration: DeepLinkConfiguration(presets: [], delivery: delivery, openURL: nil),
                system: FakeSystemURLOpening(),
                store: FakeDeepLinkHistoryStore()
            ))
            let snapshots = sut.snapshots()

            sut.send(DeepLinkCommand(.continue(DeepLinkActivity(activityType: "com.example.app.compose", webpageURL: nil, userInfo: []))))
            for await snapshot in snapshots where snapshot.outcome != nil {
                break
            }

            let actual = try #require(delivery.delivered.first)
            #expect(actual.userInfo?.isEmpty ?? true)
        }

        @Test("With no handler and no delegate method, the outcome tells the developer to pass continueUserActivity:")
        func unhandledOutcome() async throws {
            let sut = DebugDrawerPluginTransport.direct(to: DeepLinkModel(
                configuration: DeepLinkConfiguration(presets: [], delivery: FakeUserActivityDelivering(answer: .unhandled), openURL: nil),
                system: FakeSystemURLOpening(),
                store: FakeDeepLinkHistoryStore()
            ))
            let snapshots = sut.snapshots()
            let url = try #require(URL(string: "https://example.com/path"))
            let expected = "This app has no handler: pass continueUserActivity: to installDeepLink"

            sut.send(DeepLinkCommand(.continue(.universalLink(url))))
            for await snapshot in snapshots where snapshot.outcome != nil {
                break
            }

            let actual = try #require(sut.snapshot.outcome)
            #expect(actual.text == expected)
            #expect(actual.severity == .error)
        }

        @Test("Continued activities are listed most recent first, once each, apart from the URLs opened")
        func activityHistory() async throws {
            let sut = DebugDrawerPluginTransport.direct(to: DeepLinkModel(
                configuration: DeepLinkConfiguration(presets: [], delivery: FakeUserActivityDelivering(), openURL: nil),
                system: FakeSystemURLOpening(),
                store: FakeDeepLinkHistoryStore()
            ))
            let snapshots = sut.snapshots()
            let first = try DeepLinkActivity.universalLink(#require(URL(string: "https://example.com/a")))
            let second = DeepLinkActivity(
                activityType: "com.example.app.viewOrder", webpageURL: nil, userInfo: [UserInfoEntry(key: "orderID", value: .integer(7))]
            )
            let expected = [first, second]

            sut.send(DeepLinkCommand(.continue(first)))
            sut.send(DeepLinkCommand(.continue(second)))
            sut.send(DeepLinkCommand(.continue(first)))
            for await snapshot in snapshots where snapshot.activities == expected {
                break
            }

            #expect(sut.snapshot.activities == expected)
            #expect(sut.snapshot.history.isEmpty)
        }

        @Test("Opened URLs are listed most recent first, once each, whatever came of each open")
        func urlHistory() async throws {
            let handled = try #require(URL(string: "myapp://a"))
            let declined = try #require(URL(string: "myapp://b"))
            let sut = DebugDrawerPluginTransport.direct(to: DeepLinkModel(
                configuration: DeepLinkConfiguration(presets: [], delivery: FakeUserActivityDelivering(), openURL: { $0 == handled }),
                system: FakeSystemURLOpening(),
                store: FakeDeepLinkHistoryStore()
            ))
            let snapshots = sut.snapshots()
            let expected = ["myapp://a", "myapp://b"]

            sut.send(DeepLinkCommand(.open(handled)))
            sut.send(DeepLinkCommand(.open(declined)))
            sut.send(DeepLinkCommand(.open(handled)))
            for await snapshot in snapshots where snapshot.history == expected && snapshot.outcome == .handled("myapp://a") {
                break
            }

            #expect(sut.snapshot.history == expected)
            #expect(sut.snapshot.activities.isEmpty)
        }

        @Test("The history is kept 30 deep, saved after each send, and read back by the next model on the same store")
        func historyPersists() async throws {
            let store = FakeDeepLinkHistoryStore()
            let sut = DebugDrawerPluginTransport.direct(to: DeepLinkModel(
                configuration: DeepLinkConfiguration(presets: [], delivery: FakeUserActivityDelivering(), openURL: { _ in true }),
                system: FakeSystemURLOpening(),
                store: store
            ))
            let snapshots = sut.snapshots()
            let activities = (0 ..< 31).map {
                DeepLinkActivity(activityType: "com.example.app.item", webpageURL: nil, userInfo: [UserInfoEntry(key: "index", value: .integer($0))])
            }
            let urls = try (0 ..< 31).map { try #require(URL(string: "myapp://item/\($0)")) }
            let expectedActivities = Array(activities.reversed().prefix(30))
            let expectedURLs = Array(urls.reversed().prefix(30).map(\.absoluteString))
            let expectedSaves = 62

            activities.forEach { sut.send(DeepLinkCommand(.continue($0))) }
            urls.forEach { sut.send(DeepLinkCommand(.open($0))) }
            for await snapshot in snapshots where snapshot.history == expectedURLs {
                break
            }

            let actual = DeepLinkModel(
                configuration: DeepLinkConfiguration(presets: [], delivery: FakeUserActivityDelivering(), openURL: nil),
                system: FakeSystemURLOpening(),
                store: store
            ).snapshot
            #expect(store.saved.count == expectedSaves)
            #expect(actual.activities == expectedActivities)
            #expect(actual.history == expectedURLs)
        }

        @Test("Clear History empties both the URLs and the activities, here and in the store")
        func clearHistory() async throws {
            let link = try DeepLinkActivity.universalLink(#require(URL(string: "https://example.com/a")))
            let store = FakeDeepLinkHistoryStore(DeepLinkHistory(urls: ["myapp://orders/42"], activities: [link]))
            let sut = DebugDrawerPluginTransport.direct(to: DeepLinkModel(
                configuration: DeepLinkConfiguration(presets: [], delivery: FakeUserActivityDelivering(), openURL: nil),
                system: FakeSystemURLOpening(),
                store: store
            ))
            let snapshots = sut.snapshots()
            let historyBefore = sut.snapshot.history

            sut.send(DeepLinkCommand(.clearHistory))
            for await snapshot in snapshots where snapshot.history.isEmpty && snapshot.activities.isEmpty {
                break
            }

            #expect(historyBefore == ["myapp://orders/42"])
            #expect(store.kept == DeepLinkHistory())
        }

        @Test("Configuring takes the new presets and handler, and reads the history the new store keeps")
        func configureReadsTheNewStore() async throws {
            let preset = try DeepLinkPreset("Cart", url: #require(URL(string: "shop://cart")))
            var received: [URL] = []
            let first = FakeDeepLinkHistoryStore(DeepLinkHistory(urls: ["myapp://old"], activities: []))
            let second = FakeDeepLinkHistoryStore(DeepLinkHistory(urls: ["shop://kept"], activities: []))
            let model = DeepLinkModel(
                configuration: DeepLinkConfiguration(presets: [], delivery: FakeUserActivityDelivering(), openURL: nil),
                system: FakeSystemURLOpening(),
                store: first
            )
            let sut = DebugDrawerPluginTransport.direct(to: model)
            let snapshots = sut.snapshots()
            let url = try #require(URL(string: "shop://cart"))

            model.configure(
                DeepLinkConfiguration(presets: [preset], delivery: FakeUserActivityDelivering(), openURL: { received.append($0); return true }),
                store: second
            )
            sut.send(DeepLinkCommand(.open(url)))
            for await snapshot in snapshots where snapshot.outcome != nil {
                break
            }

            #expect(sut.snapshot.presets == [preset])
            #expect(sut.snapshot.history == ["shop://cart", "shop://kept"])
            #expect(received == [url])
            #expect(second.kept.urls == ["shop://cart", "shop://kept"])
            #expect(first.saved.isEmpty)
        }
    }
#endif
