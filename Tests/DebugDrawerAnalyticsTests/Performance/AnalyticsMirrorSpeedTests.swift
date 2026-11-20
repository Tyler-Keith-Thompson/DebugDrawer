// What mirroring costs the thread that records an event. It runs on the app's own threads,
// wherever it sends an event, so redaction must stay cheap: 20,000 events of five properties, each
// string matched against the standard value patterns, take a few hundred milliseconds on an Apple
// silicon Mac in a debug build; the bound is several times that, so a loaded machine passes and a
// change that compiles the patterns per event, or copies the waiting events on each one, fails.
// `--config=release` builds this target without DEBUG and runs ReleaseMirrorTests instead.
#if DEBUG
    @testable import DebugDrawerAnalytics
    @testable import DebugDrawerReceiver
    import Foundation
    import Testing

    @Suite(.timeLimit(.minutes(1)))
    struct AnalyticsMirrorSpeedTests {
        @Test("Mirroring 20,000 events through the standard redaction into a full inbox of 1,000 takes under 3 s")
        func mirrorIntoFullInbox() {
            let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
            let inboxes = AnalyticsMirrorInboxes()
            let sut = AnalyticsMirrorInbox(redaction: .standard, capacity: 1000, inboxes: inboxes) { start }
            let session = DebugDrawerSession(id: UUID(), opened: start, expires: start.addingTimeInterval(60))
            sut.open(session)
            let properties: [String: AnalyticsValue] = [
                "plan": "pro", "seats": 3, "note": "a short note about the order", "user_email": "a@b.co", "items": ["sku-1", "sku-2"]
            ]
            let clock = ContinuousClock()

            let elapsed = clock.measure {
                for index in 0 ..< 20000 {
                    inboxes.deliver(name: "event_\(index)", properties: properties, source: "Segment")
                }
            }
            let kept = sut.take(for: session.id)

            #expect(elapsed < .seconds(3))
            #expect(kept.count == 1000)
            #expect(kept.last?.id == 20000)
        }

        @Test("While no session mirrors, delivering 100,000 events takes under 500 ms")
        func deliverWithNoSession() {
            let inboxes = AnalyticsMirrorInboxes()
            let properties: [String: AnalyticsValue] = ["plan": "pro", "seats": 3]
            let clock = ContinuousClock()

            let elapsed = clock.measure {
                for _ in 0 ..< 100_000 where inboxes.isMirroring {
                    inboxes.deliver(name: "event", properties: properties, source: nil)
                }
            }

            #expect(elapsed < .milliseconds(500))
            #expect(!inboxes.isMirroring)
        }
    }
#endif
