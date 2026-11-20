import Foundation
import os

// Where `AnalyticsEvents.record` finds the mirrors to hand an event to: only those whose sidecar
// session is open register here, so while none is, recording costs one lock and an empty check,
// and a release build evaluates nothing. Events arrive from any thread and `record` returns at
// once, so the set sits behind a lock rather than in an actor, which would make each record an
// asynchronous hop and could reorder events sent back to back. `OSAllocatedUnfairLock` rather than
// `Mutex`, which needs iOS 18; switch once iOS 18 is the minimum.

/// The inboxes of the mirrors whose session is open now.
final class AnalyticsMirrorInboxes: Sendable {
    /// The inboxes `AnalyticsEvents.record` delivers to, for the life of the app.
    static let shared = AnalyticsMirrorInboxes()

    private let inboxes = OSAllocatedUnfairLock<[ObjectIdentifier: AnalyticsMirrorInbox]>(initialState: [:])

    /// Whether any mirror's session is open, so an event recorded now would be mirrored.
    var isMirroring: Bool {
        inboxes.withLock { !$0.isEmpty }
    }

    /// Delivers `inbox` the events recorded from now on, until ``remove(_:)``.
    func add(_ inbox: AnalyticsMirrorInbox) {
        inboxes.withLock { $0[ObjectIdentifier(inbox)] = inbox }
    }

    /// Stops delivering to `inbox`.
    func remove(_ inbox: AnalyticsMirrorInbox) {
        inboxes.withLock { $0[ObjectIdentifier(inbox)] = nil }
    }

    /// Hands an event recorded now to every inbox whose session is open.
    func deliver(name: String, properties: [String: AnalyticsValue], source: String?) {
        let open = inboxes.withLock { Array($0.values) }
        for inbox in open {
            inbox.receive(name: name, properties: properties, source: source)
        }
    }
}
