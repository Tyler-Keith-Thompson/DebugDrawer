import Combine
import Foundation
import os

// The diagnostics capture capability's model (DD-112, the charter's D9). It lives in the receiver,
// beside log levels and experiment overrides, rather than in a capability module: a capability
// module is a plugin's UI-free half (modules.py), and this one shares nothing with the Console or
// Network plugins, whose lines and entries are debug-only types filled by interception. Here the app
// hands over what it already has, from its own logger's backend and its own networking code, so the
// receiver still intercepts nothing: no os_log reading (OSLogClient stays the debug Console's), no
// URL protocol, no swizzling. Rejected: capturing requests through a URL protocol the host lists, as
// network mocking answers them (a protocol that claims a request must load it itself, so the
// library would re-send the app's traffic outside the app's session and its delegate, the very
// change DD-62 and DD-63 fixed in the debug plugin); a capture that starts as any session opens (a
// session opened only to override a flag would collect customers' data nobody asked for); and
// keeping the app's copy after the session when the sidecar exported it (customer data left in the
// shared container with no session to expire it).
//
// Where the data is: in memory, and in the capability's snapshot file in the app's own directory of
// the group's store (`apps/<bundle ID>/snapshots/`), which the receiver writes and the sidecar
// reads; nowhere else. So deleting the capture is emptying the snapshot and removing that file: the
// model does both as its capture stops (the sidecar's stop, the session's end, expiry or a gate
// turning it off, through the scope's revert), and removes the file as the receiver enables it,
// before anything is captured, which deletes what a launch killed during a session left behind.

/// Console lines and network requests the app hands it, captured redacted and bounded while a
/// sidecar's session asks for them, for a production build.
///
/// The app makes it with the receiver's sessions, enables the capability, and forwards what it
/// logs and the requests it sends:
///
/// ```swift
/// let capture = DebugDrawerDiagnosticsCapture(sessions: sessions)
/// receiver.enable(.diagnosticsCapture(capture))
///
/// capture.log(level: .error, message: "Payment declined", metadata: ["order": "1042"], subsystem: "com.example.shop")
///
/// let started = Date()
/// let (data, response) = try await session.data(for: request)
/// capture.record(request, response: response, body: data, started: started)
/// ```
///
/// It captures nothing until a sidecar, in an open session, sends ``Command/start``, and stops
/// and deletes everything it captured as the session ends or expires, as the sidecar sends
/// ``Command/stop``, or as a gate turns it off. Outside a capture, ``log(level:message:metadata:subsystem:category:)``
/// and ``record(_:response:body:error:started:)`` do nothing and evaluate none of their arguments.
/// Everything kept is redacted first (``redaction``) and bounded (``limits``). A sidecar exports a
/// copy into its report with ``Command/export``, which the app records in ``Snapshot/exports`` and
/// the sessions' audit log; the app's own copy is deleted with the session either way.
@MainActor
public final class DebugDrawerDiagnosticsCapture: DebugDrawerPluginModel {
    private static let logger = Logger(subsystem: "DebugDrawerReceiver", category: "DiagnosticsCapture")

    /// The ID the receiver serves it under.
    public static let pluginID = "DebugDrawer.DiagnosticsCapture"

    /// What a sidecar asks.
    public enum Command: Codable, Equatable, Sendable {
        /// Starts capturing in the open session, empty; does nothing while it captures already.
        case start
        /// Stops capturing and deletes everything captured; what the session's end performs.
        case stop
        /// Records that the sidecar took a copy of the capture into its report, with how much it
        /// held; does nothing while it isn't capturing.
        case export
    }

    /// The capture now: empty while it isn't capturing.
    @Published public private(set) var snapshot: Snapshot

    /// The rules every line and request is redacted by before it is kept.
    public nonisolated var redaction: DebugDrawerDiagnosticsRedaction {
        inbox.redaction
    }

    /// The bounds the capture keeps to.
    public nonisolated var limits: Limits {
        inbox.limits
    }

    private nonisolated let inbox: DiagnosticsCaptureInbox
    private let now: @Sendable () -> Date
    /// The session open now, as the sessions last said.
    private var openSession: DebugDrawerSession?
    /// Where the receiver writes the snapshot, once one enabled the capability.
    private var snapshotFile: URL?
    private var sessionObservation: AnyCancellable?

    /// A capture that runs within `sessions`' sessions, as a sidecar starts it.
    ///
    /// - Parameters:
    ///   - sessions: The receiver's sessions.
    ///   - redaction: The rules every line and request is redacted by;
    ///     ``DebugDrawerDiagnosticsRedaction/standard`` unless given.
    ///   - limits: The bounds of one session's capture; ``Limits/standard`` unless given.
    public convenience init(
        sessions: DebugDrawerSessions,
        redaction: DebugDrawerDiagnosticsRedaction = .standard,
        limits: Limits = .standard
    ) {
        self.init(sessions: sessions, redaction: redaction, limits: limits) { Date() }
    }

    /// A capture that dates what it captures by `now`.
    ///
    /// - Parameters:
    ///   - sessions: The receiver's sessions.
    ///   - redaction: The rules every line and request is redacted by.
    ///   - limits: The bounds of one session's capture.
    ///   - now: The time a line or request is captured at, checked against the session's expiry.
    package init(
        sessions: DebugDrawerSessions,
        redaction: DebugDrawerDiagnosticsRedaction,
        limits: Limits,
        now: @escaping @Sendable () -> Date
    ) {
        inbox = DiagnosticsCaptureInbox(redaction: redaction, limits: limits, now: now)
        self.now = now
        snapshot = Snapshot(sessionID: nil, lines: [], requests: [], dropped: 0, byteCount: 0, limits: limits, exports: [])
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
        case .start:
            guard let openSession, snapshot.sessionID != openSession.id else { return }
            inbox.open(openSession)
            snapshot = Snapshot(sessionID: openSession.id, lines: [], requests: [], dropped: 0, byteCount: 0, limits: limits, exports: [])
            Self.logger.notice("Diagnostics capture started for a sidecar's session")
        case .stop:
            discard()
        case .export:
            guard snapshot.isCapturing else { return }
            collect()
            let export = Export(date: now(), lines: snapshot.lines.count, requests: snapshot.requests.count)
            snapshot.exports.append(export)
            Self.logger.notice(
                "A sidecar exported the diagnostics capture: \(export.lines, privacy: .public) lines, \(export.requests, privacy: .public) requests"
            )
        }
    }

    /// Captures a line the app logged, redacted, while a sidecar's capture runs. Otherwise it does
    /// nothing and evaluates none of its arguments.
    ///
    /// Call it from any thread or actor, from the app's logger's backend; it returns at once.
    ///
    /// - Parameters:
    ///   - level: How severe the line is.
    ///   - message: What was logged; the values of sensitive `key=value` pairs and the text value
    ///     patterns match are masked.
    ///   - metadata: Key/value fields; each sensitive key's value is masked.
    ///   - subsystem: What logged it (a logger's label); empty for none.
    ///   - category: Its category within the subsystem; empty for none.
    /// - Complexity: O(1) while not capturing; O(*n*) in the text while capturing, to redact it.
    public nonisolated func log(
        level: Level,
        message: @autoclosure () -> String,
        metadata: @autoclosure () -> [String: String] = [:],
        subsystem: @autoclosure () -> String = "",
        category: @autoclosure () -> String = ""
    ) {
        guard inbox.isCapturing else { return }
        inbox.receive(level: level, message: message(), metadata: metadata(), subsystem: subsystem(), category: category())
    }

    /// Captures a request the app sent and its outcome, redacted, while a sidecar's capture runs.
    /// Otherwise it does nothing and evaluates none of its arguments.
    ///
    /// Call it once the app has the outcome, from any thread or actor; it returns at once. It reads
    /// the values it is given and nothing else: it sends nothing and changes nothing about the
    /// request or the response.
    ///
    /// - Parameters:
    ///   - request: The request as the app sent it; its URL, headers and `httpBody` are captured.
    ///   - response: The response, if one came.
    ///   - body: The response's body, if any; kept only when it is JSON and no larger than
    ///     ``Limits/bodyBytes``.
    ///   - error: The failure, if it failed; only its domain and code are kept.
    ///   - started: When the app sent it.
    /// - Complexity: O(*n*) in the request and response while capturing, to redact them.
    public nonisolated func record(
        _ request: @autoclosure () -> URLRequest,
        response: @autoclosure () -> URLResponse? = nil,
        body: @autoclosure () -> Data? = nil,
        error: @autoclosure () -> (any Error)? = nil,
        started: @autoclosure () -> Date
    ) {
        guard inbox.isCapturing else { return }
        inbox.receive(request: request(), response: response(), body: body(), error: error(), started: started())
    }

    /// The newest `count` lines captured for the session `sessionID` names, taken from the capture
    /// now rather than from the last snapshot, or `nil` when it isn't capturing for that session:
    /// the lines a bug report the host triggers (``DebugDrawerBugReports``) copies.
    package func recentLines(_ count: Int, inSession sessionID: UUID) -> [LogLine]? {
        collect()
        guard snapshot.sessionID == sessionID else { return nil }
        return Array(snapshot.lines.suffix(max(count, 0)))
    }

    /// Takes the file the receiver writes the snapshot to, and removes what is there: a capture
    /// made fresh holds nothing, so anything there was left by a launch killed during a session.
    package func attach(snapshotFile file: URL) {
        snapshotFile = file
        removeSnapshotFile()
    }

    /// Follows the open session, and stops and deletes the capture when its session is over.
    private func follow(_ state: DebugDrawerSessionState) {
        openSession = state.session
        if let capturing = snapshot.sessionID, state.session?.id != capturing {
            discard()
        }
    }

    /// Stops capturing and deletes everything captured, in memory and on disk; does nothing while
    /// it isn't capturing, so the empty snapshot the receiver serves then stays.
    private func discard() {
        guard snapshot.isCapturing else { return }
        inbox.close()
        snapshot = Snapshot(sessionID: nil, lines: [], requests: [], dropped: 0, byteCount: 0, limits: limits, exports: [])
        // The receiver writes the empty snapshot after this, as it follows each change.
        removeSnapshotFile()
        Self.logger.notice("Diagnostics capture stopped, and what it captured deleted")
    }

    private func removeSnapshotFile() {
        guard let snapshotFile, FileManager.default.fileExists(atPath: snapshotFile.path) else { return }
        do {
            try FileManager.default.removeItem(at: snapshotFile)
        } catch {
            Self.logger.error("Couldn't remove the diagnostics capture's file: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Takes what the inbox captured for the session into the snapshot.
    private func collect() {
        guard let sessionID = snapshot.sessionID else { return }
        let state = inbox.current()
        guard state.session?.id == sessionID else { return }
        // One assignment, so a reader never sees the lines of one moment with the counts of another.
        var collected = snapshot
        collected.lines = state.lines
        collected.requests = state.requests
        collected.dropped = state.dropped
        collected.byteCount = state.byteCount
        snapshot = collected
    }
}
