import Combine
import DebugDrawerReceiver
import Foundation

// The MetricKit capability's model. Capture and serving are apart, as a crash and the session
// that reads it are: MetricKit delivers a crash's diagnostic on a later launch, before any sidecar
// can have opened a session, so every payload is redacted and kept in the app's own directory as
// it arrives (MetricKitPayloadArchive), and the snapshot holds them only while a session is open,
// emptied as it ends or expires. The sessions' rule that commands outside a session are refused
// is about changing the app; serving is a separate choice, and this one makes it the same way:
// nothing leaves the app's own storage for the shared container until someone is debugging, so a
// sidecar installed beside the app, or any app in the group, reads nothing between sessions. Under
// a grant policy a session whose grant doesn't list the capability is served nothing either, as the
// sessions only check grants against commands.
// Rejected: serving whenever enabled (crash data in the shared container all the time, though no
// one asked for it); keeping payloads in the app group's container (the same, at rest); serving
// only what arrives during a session, as the analytics capability does (a crash would never
// reach the sidecar, since it always arrives before); a signal or exception handler in release
// (interception in the build that ships, which the charter's N1 rules out, and a second crash
// handler racing the app's crash SDK; MetricKit's report is the system's, written out of process).

/// The MetricKit payloads the app received (daily metrics, and diagnostics: crashes, hangs, CPU
/// and disk-write exceptions), redacted and kept across launches, which the receiver serves under
/// ``pluginID`` while a sidecar's session is open.
///
/// The receiver makes it for
/// `DebugDrawerReceiverCapability.metricKitPayloads(sessions:directory:redaction:capacity:)`; a
/// sidecar connects to ``pluginID`` with ``Snapshot`` and ``Command``:
///
/// ```swift
/// let payloads = try await sidecar.connect(
///     toPlugin: MetricKitPayloadsMirror.pluginID,
///     snapshot: MetricKitPayloadsMirror.Snapshot.self,
///     command: MetricKitPayloadsMirror.Command.self
/// )
/// ```
@MainActor
public final class MetricKitPayloadsMirror: DebugDrawerPluginModel {
    /// The ID the receiver serves it under.
    public static let pluginID = "DebugDrawer.MetricKitPayloads"
    /// How many payloads are kept unless the host says otherwise: a week of daily metrics and
    /// three diagnostics.
    public static let defaultCapacity = 10
    /// The most bytes a payload's redacted JSON may hold, a megabyte; a larger one is dropped, so
    /// a snapshot holds at most a megabyte of JSON per payload of its capacity.
    public static let maximumPayloadSize = 1024 * 1024

    /// Where payloads are kept unless the capability is given another: a folder in the app's
    /// Application Support directory, named after its bundle identifier, as on macOS that
    /// directory is shared by every app that isn't sandboxed.
    public static var defaultDirectory: URL {
        URL.applicationSupportDirectory
            .appending(path: Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName, directoryHint: .isDirectory)
            .appending(path: "DebugDrawer Sidecar MetricKit Payloads", directoryHint: .isDirectory)
    }

    /// One payload MetricKit delivered, as the redaction left it.
    public struct Payload: Codable, Equatable, Identifiable, Sendable {
        /// Its identity, the same in every session and launch.
        public let id: UUID
        /// Whether it holds metrics or diagnostics; a crash is a diagnostic payload's
        /// `crashDiagnostics`.
        public let kind: MetricKitPayloadKind
        /// The start of the period it covers.
        public let begin: Date
        /// The end of the period it covers.
        public let end: Date
        /// When the app received it.
        public let received: Date
        /// Its `jsonRepresentation()`, compact, keys sorted, each value the redaction names
        /// masked.
        public let json: Data

        /// A payload.
        ///
        /// - Parameters:
        ///   - id: Its identity.
        ///   - kind: Metrics or diagnostics.
        ///   - begin: The start of its period.
        ///   - end: The end of its period.
        ///   - received: When the app received it.
        ///   - json: Its JSON object.
        public init(id: UUID, kind: MetricKitPayloadKind, begin: Date, end: Date, received: Date, json: Data) {
            self.id = id
            self.kind = kind
            self.begin = begin
            self.end = end
            self.received = received
            self.json = json
        }
    }

    /// What a sidecar sees.
    public struct Snapshot: Codable, Equatable, Sendable {
        /// The open session's ID, or `nil` while none is open.
        public var sessionID: UUID?
        /// The payloads kept, the latest period first; none while no session is open.
        public var payloads: [Payload]

        /// A snapshot.
        ///
        /// - Parameters:
        ///   - sessionID: The open session's ID, or `nil`.
        ///   - payloads: The payloads, the latest period first.
        public init(sessionID: UUID?, payloads: [Payload]) {
            self.sessionID = sessionID
            self.payloads = payloads
        }
    }

    /// What a sidecar asks.
    public enum Command: Codable, Equatable, Sendable {
        /// Deletes the payload with `id` from the app, such as once the sidecar has sent it on;
        /// MetricKit delivering it again doesn't bring it back.
        case delete(id: UUID)
        /// Deletes every payload kept.
        case deleteAll
    }

    /// The payloads now, while a session is open.
    @Published public private(set) var snapshot = Snapshot(sessionID: nil, payloads: [])

    /// The rules every payload is redacted by before it is kept.
    public let redaction: MetricKitRedaction

    /// The most payloads kept; a newer one drops the one whose period ended first.
    public var capacity: Int {
        archive.capacity
    }

    private let archive: MetricKitPayloadArchive
    private let source: (any MetricKitPayloadSource)?
    private let now: () -> Date
    private var sessionObservation: AnyCancellable?
    /// Whether the open session is served: one is open, and its grant, if it has one, lists the
    /// capability.
    private var isServing = false

    /// A mirror that keeps what `source` delivers in `directory` and serves it during `sessions`'
    /// open session.
    ///
    /// - Parameters:
    ///   - sessions: The receiver's sessions.
    ///   - directory: Where the payloads are kept.
    ///   - redaction: The rules each payload is redacted by.
    ///   - capacity: The most payloads kept.
    ///   - maximumPayloadSize: The most bytes a kept payload's JSON holds.
    ///   - source: Where payloads come from; `nil` keeps none.
    ///   - now: When a payload arrives.
    /// - Precondition: `capacity` is at least 1.
    package init(
        sessions: DebugDrawerSessions,
        directory: URL,
        redaction: MetricKitRedaction,
        capacity: Int,
        maximumPayloadSize: Int = MetricKitPayloadsMirror.maximumPayloadSize,
        source: (any MetricKitPayloadSource)?,
        now: @escaping () -> Date = { Date() }
    ) {
        precondition(capacity > 0, "The MetricKit mirror keeps at least one payload")
        self.redaction = redaction
        self.source = source
        self.now = now
        archive = MetricKitPayloadArchive(directory: directory, capacity: capacity, maximumPayloadSize: maximumPayloadSize)
        // The sessions are main-actor isolated and publish from there.
        sessionObservation = sessions.$snapshot.sink { [weak self] state in
            MainActor.assumeIsolated {
                self?.follow(state)
            }
        }
        // Last, as the source hands over the payloads it holds as it subscribes.
        source?.subscribe { [weak self] received in
            self?.receive(received)
        }
    }

    isolated deinit {
        source?.unsubscribe()
    }

    /// Does what `command` asks.
    ///
    /// - Parameter command: What to do.
    public func perform(_ command: Command) {
        let ids: Set<UUID> = switch command {
        case let .delete(id): [id]
        case .deleteAll: Set(archive.payloads.map(\.id))
        }
        if archive.delete(ids) {
            publish()
        }
    }

    /// Keeps what arrived, and shows it if a session is open.
    private func receive(_ received: [ReceivedMetricKitPayload]) {
        if archive.receive(received, redaction: redaction, at: now()) {
            publish()
        }
    }

    /// Serves the payloads as a session opens whose grant, if it has one, lists the capability,
    /// and none as it ends or expires.
    private func follow(_ state: DebugDrawerSessionState) {
        let session = state.session
        guard session?.id != snapshot.sessionID else { return }
        isServing = session?.allows(Self.pluginID) ?? false
        snapshot = Snapshot(sessionID: session?.id, payloads: isServing ? archive.payloads : [])
    }

    private func publish() {
        guard isServing else { return }
        snapshot.payloads = archive.payloads
    }
}
