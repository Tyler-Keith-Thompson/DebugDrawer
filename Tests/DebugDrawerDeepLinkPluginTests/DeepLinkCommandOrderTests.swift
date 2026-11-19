#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerDeepLinkPlugin
    import Foundation
    import Testing

    // The fake opener holds an open until the test releases it, so later commands are sent while
    // it waits; each must run after it, as sent.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct DeepLinkCommandOrderTests {
        @Test("An open sent while another waits on the system starts only once that one is done, so the last outcome is the last sent")
        func opensRunInOrder() async throws {
            let first = try #require(URL(string: "slow://first"))
            let second = try #require(URL(string: "fast://second"))
            let system = FakeSystemURLOpening(held: [first])
            let sut = DebugDrawerPluginTransport.direct(to: DeepLinkModel(
                configuration: DeepLinkConfiguration(presets: [], delivery: FakeUserActivityDelivering(), openURL: nil),
                system: system,
                store: FakeDeepLinkHistoryStore()
            ))
            let snapshots = sut.snapshots()
            sut.send(DeepLinkCommand(.open(first)))
            for await snapshot in snapshots where snapshot.history == ["slow://first"] {
                break
            }

            sut.send(DeepLinkCommand(.open(second)))
            let openedWhileHeld = system.opened
            system.release()
            for await snapshot in snapshots where snapshot.outcome == .opened("fast://second") {
                break
            }

            #expect(openedWhileHeld == [first])
            #expect(system.finished == [first, second])
            #expect(sut.snapshot.history == ["fast://second", "slow://first"])
            #expect(sut.snapshot.outcome == .opened("fast://second"))
        }

        @Test("A continue sent while an open waits is delivered after it, and its outcome is the one left")
        func continueWaitsForOpen() async throws {
            let url = try #require(URL(string: "slow://first"))
            let link = try DeepLinkActivity.universalLink(#require(URL(string: "https://example.com/a")))
            let system = FakeSystemURLOpening(held: [url])
            let delivery = FakeUserActivityDelivering()
            let sut = DebugDrawerPluginTransport.direct(to: DeepLinkModel(
                configuration: DeepLinkConfiguration(presets: [], delivery: delivery, openURL: nil),
                system: system,
                store: FakeDeepLinkHistoryStore()
            ))
            let snapshots = sut.snapshots()
            sut.send(DeepLinkCommand(.open(url)))
            for await snapshot in snapshots where snapshot.history == ["slow://first"] {
                break
            }

            sut.send(DeepLinkCommand(.continue(link)))
            let deliveredWhileHeld = delivery.delivered.count
            system.release()
            for await snapshot in snapshots where snapshot.outcome == .continued(.handler) {
                break
            }

            #expect(deliveredWhileHeld == 0)
            #expect(system.finished == [url])
            #expect(delivery.delivered.count == 1)
            #expect(sut.snapshot.activities == [link])
            #expect(sut.snapshot.outcome == .continued(.handler))
        }

        @Test("Clear History sent right after an open clears what that open recorded")
        func clearAfterOpen() async throws {
            let url = try #require(URL(string: "myapp://orders/42"))
            let store = FakeDeepLinkHistoryStore()
            let sut = DebugDrawerPluginTransport.direct(to: DeepLinkModel(
                configuration: DeepLinkConfiguration(presets: [], delivery: FakeUserActivityDelivering(), openURL: nil),
                system: FakeSystemURLOpening(),
                store: store
            ))
            let snapshots = sut.snapshots()
            let expectedSaves = [DeepLinkHistory(urls: ["myapp://orders/42"], activities: []), DeepLinkHistory()]

            sut.send(DeepLinkCommand(.open(url)))
            sut.send(DeepLinkCommand(.clearHistory))
            for await snapshot in snapshots where snapshot.outcome == .opened("myapp://orders/42") && snapshot.history.isEmpty {
                break
            }

            #expect(store.saved == expectedSaves)
            #expect(sut.snapshot.history.isEmpty)
        }
    }
#endif
