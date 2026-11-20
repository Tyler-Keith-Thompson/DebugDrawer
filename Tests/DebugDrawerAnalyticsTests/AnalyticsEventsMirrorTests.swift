// The mirror's model and inbox without a receiver. Events go to an inbox registry of the test's own
// rather than the one AnalyticsEvents.record reaches, so other tests recording at the same time
// can't reach it.
@testable import DebugDrawerAnalytics
@testable import DebugDrawerReceiver
import Foundation
import os
import Testing

/// A wall clock the test moves by hand.
private final class MovableClock: SessionClock, Sendable {
    private let time: OSAllocatedUnfairLock<Date>

    init(_ start: Date) {
        time = OSAllocatedUnfairLock(initialState: start)
    }

    var now: Date {
        time.withLock { $0 }
    }

    func advance(by interval: TimeInterval) {
        time.withLock { $0 += interval }
    }
}

/// A session timer that never fires: the tests end sessions themselves.
@MainActor
private final class IdleTimer: SessionTimer {
    func schedule(at date: Date, _ fire: @escaping @MainActor () -> Void) {}
    func cancel() {}
}

/// Accepts every token as a grant for `audience` listing `capabilities`, valid at any time, under
/// an ID of the token itself, so each token opens one session: it stands in for a company's grant
/// server.
private struct AcceptingGrantVerifier: DebugDrawerGrantVerifier {
    let audience: String
    let capabilities: [String]

    func verify(_ token: String) throws(DebugDrawerGrantVerificationError) -> DebugDrawerGrant {
        DebugDrawerGrant(
            id: token, subject: "employee@example.com", audiences: [audience], capabilities: capabilities,
            notBefore: .distantPast, expires: .distantFuture
        )
    }
}

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct AnalyticsEventsMirrorTests {
    private static let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test("An inbox takes nothing before its session opens, nothing at or after its expiry, and nothing once closed")
    func inboxGates() {
        let clock = MovableClock(Self.start)
        let inboxes = AnalyticsMirrorInboxes()
        let sut = AnalyticsMirrorInbox(redaction: .standard, capacity: 10, inboxes: inboxes) { clock.now }
        let session = DebugDrawerSession(id: UUID(), opened: Self.start, expires: Self.start.addingTimeInterval(60))

        sut.receive(name: "before", properties: [:], source: nil)
        let wasMirroringBefore = inboxes.isMirroring
        sut.open(session)
        let isMirroringDuring = inboxes.isMirroring
        sut.receive(name: "during", properties: ["email": "a@b.co"], source: "")
        clock.advance(by: 60)
        sut.receive(name: "at-expiry", properties: [:], source: nil)
        let taken = sut.take(for: session.id)
        let takenForAnother = sut.take(for: UUID())
        sut.close()
        sut.receive(name: "closed", properties: [:], source: nil)

        #expect(!wasMirroringBefore)
        #expect(isMirroringDuring)
        let expected = [AnalyticsEventsMirror.Event(id: 1, timestamp: Self.start, name: "during", properties: ["email": "[REDACTED]"], source: nil)]
        #expect(taken == expected)
        #expect(takenForAnother.isEmpty)
        #expect(sut.take(for: session.id).isEmpty)
        #expect(!inboxes.isMirroring)
    }

    @Test("The mirror follows the sessions: a session's events, numbered from 1, then none once it ends, and a new list for the next")
    func followsSessions() async {
        let clock = MovableClock(Self.start)
        let inboxes = AnalyticsMirrorInboxes()
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 10, clock: clock, timer: IdleTimer())
        let sut = AnalyticsEventsMirror(sessions: sessions, redaction: .none, capacity: 10, inboxes: inboxes) { clock.now }
        let (published, publish) = AsyncStream<AnalyticsEventsMirror.Snapshot>.makeStream()
        let subscription = sut.$snapshot.sink { publish.yield($0) }
        defer { subscription.cancel() }
        var changes = published.makeAsyncIterator()

        inboxes.deliver(name: "before", properties: [:], source: nil)
        sessions.perform(.open(duration: 60))
        let firstSession = sessions.snapshot.session?.id
        inboxes.deliver(name: "one", properties: [:], source: nil)
        inboxes.deliver(name: "two", properties: [:], source: nil)
        var during = sut.snapshot
        while during.events.count < 2, let next = await changes.next() {
            during = next
        }
        sessions.end()
        let ended = sut.snapshot
        inboxes.deliver(name: "after", properties: [:], source: nil)
        sessions.perform(.open(duration: 60))
        inboxes.deliver(name: "next", properties: [:], source: nil)
        var next = sut.snapshot
        while next.events.isEmpty, let change = await changes.next() {
            next = change
        }

        #expect(during.sessionID == firstSession)
        #expect(during.events.map(\.name) == ["one", "two"])
        #expect(during.events.map(\.id) == [1, 2])
        #expect(ended == AnalyticsEventsMirror.Snapshot(sessionID: nil, events: []))
        #expect(next.sessionID == sessions.snapshot.session?.id)
        #expect(next.events.map(\.name) == ["next"])
        #expect(next.events.map(\.id) == [1])
    }

    @Test("A snapshot keeps the newest events up to the capacity; clear drops them and later ones still arrive")
    func capacityAndClear() async {
        let clock = MovableClock(Self.start)
        let inboxes = AnalyticsMirrorInboxes()
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 10, clock: clock, timer: IdleTimer())
        let sut = AnalyticsEventsMirror(sessions: sessions, redaction: .none, capacity: 2, inboxes: inboxes) { clock.now }
        let (published, publish) = AsyncStream<AnalyticsEventsMirror.Snapshot>.makeStream()
        let subscription = sut.$snapshot.sink { publish.yield($0) }
        defer { subscription.cancel() }
        var changes = published.makeAsyncIterator()
        sessions.perform(.open(duration: 60))

        for name in ["a", "b", "c"] {
            inboxes.deliver(name: name, properties: [:], source: nil)
        }
        var full = sut.snapshot
        while full.events.last?.name != "c", let next = await changes.next() {
            full = next
        }
        sut.perform(.clear)
        let cleared = sut.snapshot
        inboxes.deliver(name: "d", properties: [:], source: nil)
        var later = sut.snapshot
        while later.events.isEmpty, let next = await changes.next() {
            later = next
        }

        #expect(full.events.map(\.name) == ["b", "c"])
        #expect(cleared.events.isEmpty)
        #expect(cleared.sessionID == sessions.snapshot.session?.id)
        #expect(later.events.map(\.name) == ["d"])
        #expect(later.events.map(\.id) == [4])
    }

    @Test("A number JSON can't write arrives as its description, so the snapshot still encodes, and decodes to what was mirrored")
    func nonFiniteNumbersEncode() async throws {
        let clock = MovableClock(Self.start)
        let inboxes = AnalyticsMirrorInboxes()
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 10, clock: clock, timer: IdleTimer())
        let sut = AnalyticsEventsMirror(sessions: sessions, redaction: .none, capacity: 10, inboxes: inboxes) { clock.now }
        let (published, publish) = AsyncStream<AnalyticsEventsMirror.Snapshot>.makeStream()
        let subscription = sut.$snapshot.sink { publish.yield($0) }
        defer { subscription.cancel() }
        var changes = published.makeAsyncIterator()
        sessions.perform(.open(duration: 60))
        let date = Date(timeIntervalSinceReferenceDate: 1234.5)
        let expected: [String: AnalyticsValue] = [
            "nan": "nan", "up": "inf", "down": "-inf", "nested": ["inf"], "whole": 3.0, "when": .date(date), "none": nil
        ]

        inboxes.deliver(name: "odd", properties: [
            "nan": .double(.nan), "up": .double(.infinity), "down": .double(-.infinity), "nested": [.double(.infinity)],
            "whole": 3.0, "when": .date(date), "none": nil
        ], source: nil)
        var snapshot = sut.snapshot
        while snapshot.events.isEmpty, let next = await changes.next() {
            snapshot = next
        }
        let decoded = try JSONDecoder().decode(AnalyticsEventsMirror.Snapshot.self, from: JSONEncoder().encode(snapshot))

        #expect(snapshot.events.first?.properties == expected)
        #expect(decoded == snapshot)
    }

    @Test("Under a grant policy, a session whose grant doesn't list the capability is mirrored no events: its inbox never opens")
    func grantWithoutCapability() {
        let clock = MovableClock(Self.start)
        let inboxes = AnalyticsMirrorInboxes()
        let policy = DebugDrawerGrantPolicy(
            verifier: AcceptingGrantVerifier(audience: "com.example.app", capabilities: ["DebugDrawer.FeatureFlagOverrides"]),
            audience: "com.example.app"
        )
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 10, grantPolicy: policy, clock: clock, timer: IdleTimer())
        let sut = AnalyticsEventsMirror(sessions: sessions, redaction: .none, capacity: 10, inboxes: inboxes) { clock.now }

        sessions.perform(.open(duration: 60, grant: "flags-only"))
        let isMirroring = inboxes.isMirroring
        inboxes.deliver(name: "checkout_completed", properties: ["plan": "pro"], source: nil)

        #expect(sessions.snapshot.isActive)
        #expect(!isMirroring)
        let expected = AnalyticsEventsMirror.Snapshot(sessionID: sessions.snapshot.session?.id, events: [])
        #expect(sut.snapshot == expected)
    }

    @Test("Under a grant policy, a session whose grant lists the capability is mirrored its events")
    func grantWithCapability() async {
        let clock = MovableClock(Self.start)
        let inboxes = AnalyticsMirrorInboxes()
        let policy = DebugDrawerGrantPolicy(
            verifier: AcceptingGrantVerifier(audience: "com.example.app", capabilities: [AnalyticsEventsMirror.pluginID]),
            audience: "com.example.app"
        )
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 10, grantPolicy: policy, clock: clock, timer: IdleTimer())
        let sut = AnalyticsEventsMirror(sessions: sessions, redaction: .none, capacity: 10, inboxes: inboxes) { clock.now }
        let (published, publish) = AsyncStream<AnalyticsEventsMirror.Snapshot>.makeStream()
        let subscription = sut.$snapshot.sink { publish.yield($0) }
        defer { subscription.cancel() }
        var changes = published.makeAsyncIterator()
        let expected = ["checkout_completed"]

        sessions.perform(.open(duration: 60, grant: "analytics"))
        inboxes.deliver(name: "checkout_completed", properties: ["plan": "pro"], source: nil)
        var actual = sut.snapshot
        while actual.events.isEmpty, let next = await changes.next() {
            actual = next
        }

        #expect(actual.sessionID == sessions.snapshot.session?.id)
        #expect(actual.events.map(\.name) == expected)
    }
}
