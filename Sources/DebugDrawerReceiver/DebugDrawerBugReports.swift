import Combine
import Foundation
import os

// The dogfood bug report capability's model (DD-113, the charter's D9). It lives in the receiver,
// beside the diagnostics capture whose lines it copies, rather than in a capability module: a
// capability module is a plugin's UI-free half (modules.py), and a report shares nothing with the
// Screenshot plugin, whose capture is debug-only and drawn from the drawer's window.
//
// The trigger is the host's (the charter's N2): the library binds no gesture, key or button, so a
// report exists only once the host calls `trigger(note:)` from something of its own (a shake
// handler, a menu item, a feedback button). A trigger is a change the app asks for itself, so it
// goes through the receiver's gates and the sessions as a sidecar's command does
// (`DebugDrawerReceiver.applyHostChange`): refused while the receiver or the capability is turned
// off, while the capability isn't enabled, outside a session and, under a grant policy or after
// `requiringGrant()`, without a grant that lists it; audited as `commandApplied`; and its report
// deleted by the scope's revert as the session ends, expires or a gate turns it off. Outside a
// session it returns before anything is captured or audited, so a host may leave the trigger
// wired up for every user: a customer's shake does nothing and leaves no audit entry. Rejected: a
// trigger that works without a session (a report would sit in the shared container with nothing to
// delete it), a report the sidecar asks the app to take (the moment that matters is the
// employee's, in the app, not the one at which they reach the sidecar), and a trigger the library
// installs (N2).
//
// The production app never uploads: a report goes only into the capability's snapshot, which the
// sidecar reads from the store, and the sidecar sends it with its own uploader. The receiver's
// module links nothing that could send it: it depends on no other module, and the uploader
// protocol lives in the drawer's module, which a release build doesn't link.
//
// Where the data is: in memory and in the capability's snapshot file in the app's own directory of
// the store (`apps/<bundle ID>/snapshots/`), as for the diagnostics capture, and deleted the same
// way: as the session ends or expires, as a gate turns the capability off, as the sidecar deletes a
// report, and as the receiver enables the capability, which deletes what a launch killed during a
// session left behind.

/// Bug reports an employee triggers in the app during a sidecar's session: a screenshot of the
/// app's key window, the recent log lines of the session's diagnostics capture and a state snapshot
/// the host chooses, handed to the sidecar, which annotates and sends them.
///
/// The host makes it with the receiver's sessions, enables the capability, and calls
/// ``trigger(note:)`` from a trigger of its own; the library adds none:
///
/// ```swift
/// let reports = DebugDrawerBugReports(sessions: sessions, diagnostics: capture) {
///     CheckoutState(screen: router.currentScreen, cartItems: cart.count)
/// }
/// receiver.enable(.bugReports(reports))
///
/// // The app's own trigger, such as its shake handler:
/// reports.trigger(note: "Shaken on the checkout screen")
/// ```
///
/// Outside a sidecar's session ``trigger(note:)`` captures nothing and returns
/// ``TriggerResult/refused(_:)`` with ``DebugDrawerAuditEntry/Refusal/noActiveSession``. Within
/// one, it captures a ``Report``: the screenshot, bounded by ``Limits/screenshotBytes``; the
/// newest ``Limits/logLines`` lines of `diagnostics` when a sidecar started that capture in the
/// session; and `state`, encoded as JSON, redacted and bounded. The app never sends a report: the
/// sidecar reads it from the store and sends it through its own uploader. Reports are deleted as
/// the session ends or expires, as a gate turns the capability off, or as the sidecar sends
/// ``Command/delete(id:)`` or ``Command/deleteAll``.
@MainActor
public final class DebugDrawerBugReports: DebugDrawerPluginModel {
    private static let logger = Logger(subsystem: "DebugDrawerReceiver", category: "BugReports")

    /// The ID the receiver serves it under.
    public static let pluginID = "DebugDrawer.BugReports"

    /// What a sidecar asks.
    public enum Command: Codable, Equatable, Sendable {
        /// Records that the sidecar took a copy of the report into its own bug report.
        case export(id: UUID)
        /// Deletes the report.
        case delete(id: UUID)
        /// Deletes every report; what the session's end performs.
        case deleteAll
    }

    /// The reports of the session open now, oldest first: empty outside a session.
    @Published public private(set) var snapshot: Snapshot

    /// The rules the note and the state are redacted by.
    public let redaction: DebugDrawerDiagnosticsRedaction
    /// The bounds each report and the reports kept keep to.
    public let limits: Limits

    private let diagnostics: DebugDrawerDiagnosticsCapture?
    private let state: (@MainActor () -> any Encodable)?
    private let screenshot: @MainActor (_ maximumBytes: Int) -> Screenshot
    private let now: @Sendable () -> Date
    /// The session open now, as the sessions last said.
    private var openSession: DebugDrawerSession?
    /// Where the receiver writes the snapshot, once one enabled the capability.
    private var snapshotFile: URL?
    /// Applies a trigger through the receiver that enabled the capability; `nil` until one did.
    private var applyHostChange: (@MainActor (_ change: () -> DebugDrawerAuditEntry.Refusal?) -> DebugDrawerAuditEntry.Refusal?)?
    private var sessionObservation: AnyCancellable?

    /// Bug reports taken within `sessions`' sessions, as the host triggers them.
    ///
    /// - Parameters:
    ///   - sessions: The receiver's sessions.
    ///   - diagnostics: The diagnostics capture made with the same sessions, whose recent lines a
    ///     report copies while a sidecar captures; `nil` for reports without logs.
    ///   - redaction: The rules the note and the state are redacted by;
    ///     ``DebugDrawerDiagnosticsRedaction/standard`` unless given.
    ///   - limits: The bounds of each report and of the reports kept; ``Limits/standard`` unless
    ///     given.
    ///   - state: The app's state as the host chooses to show it, read on the main actor as a
    ///     report is taken, encoded as JSON and redacted; `nil` for reports without state.
    public convenience init(
        sessions: DebugDrawerSessions,
        diagnostics: DebugDrawerDiagnosticsCapture? = nil,
        redaction: DebugDrawerDiagnosticsRedaction = .standard,
        limits: Limits = .standard,
        state: (@MainActor () -> any Encodable)? = nil
    ) {
        self.init(
            sessions: sessions, diagnostics: diagnostics, redaction: redaction, limits: limits, state: state,
            screenshot: { KeyWindowScreenshot.capture(maximumBytes: $0) },
            now: { Date() }
        )
    }

    /// Bug reports that take their screenshot through `screenshot` and date what they take by `now`.
    ///
    /// - Parameters:
    ///   - sessions: The receiver's sessions.
    ///   - diagnostics: The diagnostics capture whose lines a report copies, or `nil`.
    ///   - redaction: The rules the note and the state are redacted by.
    ///   - limits: The bounds of each report and of the reports kept.
    ///   - state: The app's state, or `nil`.
    ///   - screenshot: Draws the app's window, as PNG of at most the given bytes.
    ///   - now: The time a report is taken at, checked against the session's expiry.
    package init(
        sessions: DebugDrawerSessions,
        diagnostics: DebugDrawerDiagnosticsCapture?,
        redaction: DebugDrawerDiagnosticsRedaction,
        limits: Limits,
        state: (@MainActor () -> any Encodable)?,
        screenshot: @escaping @MainActor (_ maximumBytes: Int) -> Screenshot,
        now: @escaping @Sendable () -> Date
    ) {
        self.diagnostics = diagnostics
        self.redaction = redaction
        self.limits = limits
        self.state = state
        self.screenshot = screenshot
        self.now = now
        snapshot = Snapshot(sessionID: nil, reports: [], exports: [], limits: limits)
        // The sessions are main-actor isolated and publish from there.
        sessionObservation = sessions.$snapshot.sink { [weak self] state in
            MainActor.assumeIsolated {
                self?.follow(state)
            }
        }
    }

    /// Takes a bug report of the app now, for the sidecar whose session is open: a screenshot of
    /// the key window, the recent lines of the diagnostics capture and the host's state, with
    /// `note`. Call it from the app's own trigger; the library binds none.
    ///
    /// Outside a session it captures nothing, evaluates no state and writes no audit entry, so a
    /// trigger left wired up does nothing for a customer. Until a receiver enables the capability
    /// it is refused as ``DebugDrawerAuditEntry/Refusal/unknownCapability``. Within a session, the
    /// report is refused as a sidecar's command would be, and audited: while the receiver or the
    /// capability is turned off (``DebugDrawerAuditEntry/Refusal/receiverDisabled``,
    /// ``DebugDrawerAuditEntry/Refusal/capabilityDisabled``), once it is disabled
    /// (``DebugDrawerAuditEntry/Refusal/unknownCapability``), and without a grant listing
    /// ``pluginID`` where one is needed (``DebugDrawerAuditEntry/Refusal/grantMissing``,
    /// ``DebugDrawerAuditEntry/Refusal/capabilityNotGranted``). A report taken is audited as
    /// ``DebugDrawerAuditEntry/Event/commandApplied``. Once ``Limits/reports`` are kept, the
    /// oldest goes.
    ///
    /// - Parameter note: What the person said about it, redacted; empty for none.
    /// - Returns: The report taken, or why none was.
    @discardableResult
    public func trigger(note: String = "") -> TriggerResult {
        guard let session = openSession, now() < session.expires else { return .refused(.noActiveSession) }
        guard let applyHostChange else { return .refused(.unknownCapability) }
        var taken: Report?
        let refusal = applyHostChange {
            let report = takeReport(note: note, in: session)
            keep(report, in: session)
            taken = report
            return nil
        }
        if let taken {
            Self.logger.notice("Took a bug report for a sidecar's session")
            return .captured(taken)
        }
        return .refused(refusal ?? .noActiveSession)
    }

    /// Does what `command` asks.
    ///
    /// - Parameter command: What to do.
    public func perform(_ command: Command) {
        switch command {
        case let .export(id):
            guard snapshot.reports.contains(where: { $0.id == id }) else { return }
            snapshot.exports.append(Export(reportID: id, date: now()))
            Self.logger.notice("A sidecar exported a bug report")
        case let .delete(id):
            snapshot.reports.removeAll { $0.id == id }
            if snapshot.reports.isEmpty {
                // The receiver writes the snapshot that lists none after this.
                removeSnapshotFile()
            }
        case .deleteAll:
            discard()
        }
    }

    /// Why a sidecar's `command` is refused: one naming a report the app doesn't hold is
    /// ``DebugDrawerAuditEntry/Refusal/notExposed``.
    func refusal(of command: Command) -> DebugDrawerAuditEntry.Refusal? {
        switch command {
        case let .export(id), let .delete(id):
            snapshot.reports.contains { $0.id == id } ? nil : .notExposed
        case .deleteAll:
            nil
        }
    }

    /// Takes the file the receiver writes the snapshot to, removing what is there (a model made
    /// fresh holds no report, so anything there was left by a launch killed during a session), and
    /// how the receiver applies a trigger.
    package func attach(
        snapshotFile file: URL,
        applyHostChange: @escaping @MainActor (_ change: () -> DebugDrawerAuditEntry.Refusal?) -> DebugDrawerAuditEntry.Refusal?
    ) {
        snapshotFile = file
        self.applyHostChange = applyHostChange
        removeSnapshotFile()
    }

    /// Follows the open session, and deletes the reports of a session that is over.
    private func follow(_ state: DebugDrawerSessionState) {
        openSession = state.session
        if let reported = snapshot.sessionID, state.session?.id != reported {
            discard()
        }
    }

    /// The report of the app now.
    private func takeReport(note: String, in session: DebugDrawerSession) -> Report {
        Report(
            id: UUID(),
            date: now(),
            note: redaction.redacting(text: note),
            screenshot: screenshot(limits.screenshotBytes),
            logs: diagnostics?.recentLines(limits.logLines, inSession: session.id).map(Logs.captured) ?? .notCapturing,
            state: state.map { encoded($0()) }
        )
    }

    /// Adds `report`, taken in `session`, dropping the oldest beyond ``Limits/reports``, in one
    /// assignment.
    private func keep(_ report: Report, in session: DebugDrawerSession) {
        var kept = snapshot
        kept.sessionID = session.id
        kept.reports.append(report)
        kept.reports.removeFirst(max(kept.reports.count - limits.reports, 0))
        snapshot = kept
    }

    /// `value` as JSON, redacted, or left out with its size when it is larger than
    /// ``Limits/stateBytes`` or doesn't encode.
    private func encoded(_ value: any Encodable) -> DebugDrawerDiagnosticsCapture.Body {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else { return .omitted(.notJSON, byteCount: 0) }
        guard data.count <= limits.stateBytes else { return .omitted(.tooLarge, byteCount: data.count) }
        guard let redacted = redaction.redacting(json: data), let text = String(data: redacted, encoding: .utf8) else {
            return .omitted(.notJSON, byteCount: data.count)
        }
        return .json(text)
    }

    /// Deletes every report, in memory and on disk; does nothing while there is none.
    private func discard() {
        guard snapshot.sessionID != nil else { return }
        snapshot = Snapshot(sessionID: nil, reports: [], exports: [], limits: limits)
        // The receiver writes the empty snapshot after this, as it follows each change.
        removeSnapshotFile()
        Self.logger.notice("Bug reports deleted")
    }

    private func removeSnapshotFile() {
        guard let snapshotFile, FileManager.default.fileExists(atPath: snapshotFile.path) else { return }
        do {
            try FileManager.default.removeItem(at: snapshotFile)
        } catch {
            Self.logger.error("Couldn't remove the bug reports' file: \(error.localizedDescription, privacy: .public)")
        }
    }
}
