import DebugDrawerReceiver
import Foundation
import os

// The part of a mirror that `record` reaches from any thread. It redacts each event on the
// recording thread, before it is kept anywhere, so nothing unredacted is ever held by the mirror,
// let alone written to the store; it keeps the events in the order its lock admits them, numbered
// from 1 in each session, and wakes the mirror on the main actor through a stream that keeps one
// wake-up, so a burst of events is one snapshot. An event recorded at or after the session's expiry
// is dropped even if the expiry timer hasn't fired yet, as it may not have in an app coming back
// from suspension.

/// What `AnalyticsEvents.record` hands a mirror while its session is open.
final class AnalyticsMirrorInbox: Sendable {
    private struct State {
        /// The open session, or `nil` while the mirror takes nothing.
        var session: DebugDrawerSession?
        /// The events redacted and waiting for the mirror, oldest first.
        var pending: [AnalyticsEventsMirror.Event] = []
        /// The identity of the session's next event.
        var nextID = 1
    }

    /// The rules each event is redacted by before it is kept.
    let redaction: AnalyticsRedaction
    /// The most events kept waiting; older ones are dropped.
    let capacity: Int

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let now: @Sendable () -> Date
    private let wake: AsyncStream<Void>.Continuation
    private let inboxes: AnalyticsMirrorInboxes

    /// The wake-ups: one waits after each event that arrived while none was waiting.
    let wakeUps: AsyncStream<Void>

    /// An inbox that takes nothing until ``open(_:)``.
    ///
    /// - Parameters:
    ///   - redaction: The rules each event is redacted by.
    ///   - capacity: The most events kept waiting; at least 1.
    ///   - inboxes: Where it registers while a session is open.
    ///   - now: The time an event is recorded at.
    init(redaction: AnalyticsRedaction, capacity: Int, inboxes: AnalyticsMirrorInboxes, now: @escaping @Sendable () -> Date) {
        self.redaction = redaction
        self.capacity = capacity
        self.inboxes = inboxes
        self.now = now
        (wakeUps, wake) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    /// Takes the events recorded from now until `session` expires or ``close()``, dropping any
    /// waiting from a session before.
    func open(_ session: DebugDrawerSession) {
        state.withLock { $0 = State(session: session) }
        inboxes.add(self)
    }

    /// Takes nothing more, dropping the events waiting.
    func close() {
        inboxes.remove(self)
        state.withLock { $0 = State() }
    }

    /// Closes the inbox and ends ``wakeUps``.
    func finish() {
        close()
        wake.finish()
    }

    /// Keeps the event, redacted, if a session is open and hasn't expired.
    func receive(name: String, properties: [String: AnalyticsValue], source: String?) {
        let timestamp = now()
        let name = redaction.redacting(text: name)
        let properties = redaction.redacting(properties).mapValues(\.encodable)
        let source = source.map { redaction.redacting(text: $0) }
        let kept = state.withLock { state -> Bool in
            guard let session = state.session, timestamp < session.expires else { return false }
            state.pending.append(AnalyticsEventsMirror.Event(
                id: state.nextID, timestamp: timestamp, name: name, properties: properties,
                source: source?.isEmpty == false ? source : nil
            ))
            state.nextID += 1
            if state.pending.count > capacity {
                state.pending.removeFirst(state.pending.count - capacity)
            }
            return true
        }
        if kept {
            wake.yield()
        }
    }

    /// The events waiting for `session`, oldest first, which stop waiting; none when another
    /// session, or none, is open.
    func take(for session: UUID) -> [AnalyticsEventsMirror.Event] {
        state.withLock { state in
            guard state.session?.id == session else { return [] }
            defer { state.pending = [] }
            return state.pending
        }
    }
}

extension AnalyticsValue {
    /// The value with every number JSON can't write (infinity, NaN) as its description, so a
    /// snapshot holding it still encodes.
    fileprivate var encodable: AnalyticsValue {
        switch self {
        case let .double(double) where !double.isFinite: .string("\(double)")
        case let .array(elements): .array(elements.map(\.encodable))
        case let .object(object): .object(object.mapValues(\.encodable))
        default: self
        }
    }
}
