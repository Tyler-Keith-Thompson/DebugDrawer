import Combine
import DebugDrawerReceiver
import Foundation

// The analytics capability's model. It follows the receiver's sessions itself, rather than the
// receiver telling it: a session opening starts an empty list and registers its inbox, and the
// session ending or expiring closes the inbox and empties the list, so a sidecar sees only what was
// recorded while its session was open, and nothing from before or after. Rejected: buffering events
// recorded before a session for the sidecar to read once it opens one (whatever the app sent while
// nobody was debugging would leave the process), and keeping a session's events after it ends (the
// store would hold them with no session open).

/// The analytics events recorded during the open sidecar session, redacted, as the receiver
/// serves them under ``pluginID``.
///
/// The receiver makes it for
/// `DebugDrawerReceiverCapability.analyticsEvents(sessions:redaction:capacity:)`; a sidecar connects
/// to ``pluginID`` with ``Snapshot`` and ``Command``:
///
/// ```swift
/// let events = try await sidecar.connect(
///     toPlugin: AnalyticsEventsMirror.pluginID,
///     snapshot: AnalyticsEventsMirror.Snapshot.self,
///     command: AnalyticsEventsMirror.Command.self
/// )
/// ```
@MainActor
public final class AnalyticsEventsMirror: DebugDrawerPluginModel {
    /// The ID the receiver serves it under.
    public static let pluginID = "DebugDrawer.AnalyticsEvents"
    /// How many events of a session a snapshot keeps unless the host says otherwise.
    public static let defaultCapacity = 1000

    /// One event recorded during the session, as the redaction rules left it.
    public struct Event: Codable, Equatable, Identifiable, Sendable {
        /// Its place in the order the session's events were recorded, from 1.
        public let id: Int
        /// When it was recorded.
        public let timestamp: Date
        /// Its name, or ``AnalyticsRedaction/mask`` when a value pattern matched it.
        public let name: String
        /// Its properties, each sensitive value masked; a number JSON can't write (infinity, NaN)
        /// as its description.
        public let properties: [String: AnalyticsValue]
        /// The service or SDK it was sent to, if the app named one.
        public let source: String?

        /// An event.
        ///
        /// - Parameters:
        ///   - id: Its place in the session's order, from 1.
        ///   - timestamp: When it was recorded.
        ///   - name: Its name.
        ///   - properties: Its properties.
        ///   - source: The service it was sent to, or `nil`.
        public init(id: Int, timestamp: Date, name: String, properties: [String: AnalyticsValue], source: String?) {
            self.id = id
            self.timestamp = timestamp
            self.name = name
            self.properties = properties
            self.source = source
        }
    }

    /// What a sidecar sees.
    public struct Snapshot: Codable, Equatable, Sendable {
        /// The open session's ID, or `nil` while none is open.
        public var sessionID: UUID?
        /// The newest events recorded during it, oldest first; none while no session is open.
        public var events: [Event]

        /// A snapshot.
        ///
        /// - Parameters:
        ///   - sessionID: The open session's ID, or `nil`.
        ///   - events: Its events, oldest first.
        public init(sessionID: UUID?, events: [Event]) {
            self.sessionID = sessionID
            self.events = events
        }
    }

    /// What a sidecar asks.
    public enum Command: Codable, Equatable, Sendable {
        /// Drops the events mirrored so far in this session; later ones still arrive.
        case clear
    }

    /// The open session's events now.
    @Published public private(set) var snapshot = Snapshot(sessionID: nil, events: [])

    /// The rules every event is redacted by before it is kept.
    public nonisolated var redaction: AnalyticsRedaction {
        inbox.redaction
    }

    /// The most events of a session a snapshot keeps; older ones are dropped.
    public nonisolated var capacity: Int {
        inbox.capacity
    }

    private nonisolated let inbox: AnalyticsMirrorInbox
    private var sessionObservation: AnyCancellable?

    /// A mirror of the events recorded during `sessions`' open session.
    ///
    /// - Parameters:
    ///   - sessions: The receiver's sessions.
    ///   - redaction: The rules each event is redacted by.
    ///   - capacity: The most events a snapshot keeps.
    ///   - inboxes: Where its inbox registers while a session is open.
    ///   - now: The time an event is recorded at; the sessions' clock.
    /// - Precondition: `capacity` is at least 1.
    init(
        sessions: DebugDrawerSessions,
        redaction: AnalyticsRedaction,
        capacity: Int,
        inboxes: AnalyticsMirrorInboxes = .shared,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        precondition(capacity > 0, "The analytics mirror keeps at least one event")
        inbox = AnalyticsMirrorInbox(redaction: redaction, capacity: capacity, inboxes: inboxes, now: now)
        let wakeUps = inbox.wakeUps
        Task { [weak self] in
            for await _ in wakeUps {
                self?.collect()
            }
        }
        // The sessions are main-actor isolated and publish from there.
        sessionObservation = sessions.$snapshot.sink { [weak self] state in
            MainActor.assumeIsolated {
                self?.follow(state)
            }
        }
    }

    deinit {
        inbox.finish()
    }

    /// Does what `command` asks.
    ///
    /// - Parameter command: What to do.
    public func perform(_ command: Command) {
        switch command {
        case .clear:
            guard !snapshot.events.isEmpty else { return }
            snapshot.events = []
        }
    }

    /// Starts a session's list as it opens, and empties it as it ends or expires.
    private func follow(_ state: DebugDrawerSessionState) {
        switch state.session {
        case let session? where session.id != snapshot.sessionID:
            inbox.open(session)
            snapshot = Snapshot(sessionID: session.id, events: [])
        case nil where snapshot.sessionID != nil:
            inbox.close()
            snapshot = Snapshot(sessionID: nil, events: [])
        default:
            break
        }
    }

    /// Adds the events waiting in the inbox for the open session.
    private func collect() {
        guard let sessionID = snapshot.sessionID else { return }
        let arrived = inbox.take(for: sessionID)
        guard !arrived.isEmpty else { return }
        snapshot.events = Array((snapshot.events + arrived).suffix(capacity))
    }
}
