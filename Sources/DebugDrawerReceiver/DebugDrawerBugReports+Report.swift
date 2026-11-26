import Foundation

// The vocabulary of bug reports: their bounds, a report and its parts, an export record, the
// snapshot a sidecar reads and what a trigger came to. A report holds only what redaction left of
// the note and the state; its log lines are the diagnostics capture's, already redacted there. The
// screenshot isn't redacted (an image can't be): it is what the employee had on screen as they
// triggered the report, in their own session.

extension DebugDrawerBugReports {
    /// Bounds bug reports can't keep within, which
    /// ``Limits/init(reports:logLines:stateBytes:screenshotBytes:)`` refuses.
    public enum InvalidLimits: Error, Equatable, Sendable {
        /// Fewer than 1 report would be kept.
        case noReports
        /// The most log lines a report copies is negative.
        case negativeLogLines
        /// The largest state kept is negative.
        case negativeStateBytes
        /// The largest screenshot kept is negative.
        case negativeScreenshotBytes
    }

    /// How much a report and the reports kept hold.
    public struct Limits: Codable, Equatable, Sendable {
        /// The bounds unless the host passes others: 3 reports, the newest 200 log lines each, a
        /// state of up to 64 KiB of JSON and a screenshot of up to 4 MiB of PNG.
        public static let standard = Limits(uncheckedReports: 3, logLines: 200, stateBytes: 64 << 10, screenshotBytes: 4 << 20)

        /// The most reports kept, the newest; taking another drops the oldest.
        public let reports: Int
        /// The most log lines a report copies, the newest.
        public let logLines: Int
        /// The largest state kept, in bytes of JSON; a larger one is left out, its size kept.
        public let stateBytes: Int
        /// The largest screenshot kept, in bytes of PNG; one drawn larger is drawn again at one pixel
        /// per point, and left out, its size kept, if that is still larger.
        public let screenshotBytes: Int

        /// Bounds for bug reports.
        ///
        /// - Parameters:
        ///   - reports: The most reports kept.
        ///   - logLines: The most log lines a report copies.
        ///   - stateBytes: The largest state kept, in bytes.
        ///   - screenshotBytes: The largest screenshot kept, in bytes.
        /// - Throws: ``DebugDrawerBugReports/InvalidLimits/noReports`` when `reports` is less than
        ///   1, and ``DebugDrawerBugReports/InvalidLimits/negativeLogLines``,
        ///   ``DebugDrawerBugReports/InvalidLimits/negativeStateBytes`` or
        ///   ``DebugDrawerBugReports/InvalidLimits/negativeScreenshotBytes`` when `logLines`,
        ///   `stateBytes` or `screenshotBytes` is less than 0.
        public init(reports: Int, logLines: Int, stateBytes: Int, screenshotBytes: Int) throws(InvalidLimits) {
            guard reports >= 1 else { throw .noReports }
            guard logLines >= 0 else { throw .negativeLogLines }
            guard stateBytes >= 0 else { throw .negativeStateBytes }
            guard screenshotBytes >= 0 else { throw .negativeScreenshotBytes }
            self.init(uncheckedReports: reports, logLines: logLines, stateBytes: stateBytes, screenshotBytes: screenshotBytes)
        }

        /// Bounds the caller knows are valid: ``standard``, a constant no input reaches.
        private init(uncheckedReports reports: Int, logLines: Int, stateBytes: Int, screenshotBytes: Int) {
            self.reports = reports
            self.logLines = logLines
            self.stateBytes = stateBytes
            self.screenshotBytes = screenshotBytes
        }
    }

    /// The screenshot of a report.
    public enum Screenshot: Codable, Equatable, Sendable {
        /// The app's key window, drawn by the app itself, as PNG.
        case png(Data)
        /// No window to draw: none was key, or the platform draws none (watchOS).
        case unavailable
        /// Drawn larger than ``Limits/screenshotBytes`` even at one pixel per point, so left out;
        /// its size in bytes.
        case tooLarge(byteCount: Int)
    }

    /// The log lines of a report.
    public enum Logs: Codable, Equatable, Sendable {
        /// The newest lines the session's diagnostics capture held as the report was taken, oldest
        /// first, as its redaction left them.
        case captured([DebugDrawerDiagnosticsCapture.LogLine])
        /// No diagnostics capture ran in the session: none was given, or no sidecar started it.
        case notCapturing

        /// The lines as text for a bug report, one per line, as
        /// ``DebugDrawerDiagnosticsCapture/Snapshot/consoleLog`` writes them; empty when none were
        /// captured.
        public var consoleLog: String {
            switch self {
            case let .captured(lines): lines.map(\.reportLine).joined(separator: "\n")
            case .notCapturing: ""
            }
        }
    }

    /// A bug report the host triggered.
    public struct Report: Codable, Equatable, Identifiable, Sendable {
        /// The report's identity, which a sidecar's command names.
        public let id: UUID
        /// When it was taken.
        public let date: Date
        /// What the person said about it as the host passed it, with the text value patterns
        /// matched masked.
        public let note: String
        /// The key window as it was.
        public let screenshot: Screenshot
        /// The session's recent log lines.
        public let logs: Logs
        /// The host's state as JSON, redacted, or left out with its size; `nil` when the host gave
        /// none.
        public let state: DebugDrawerDiagnosticsCapture.Body?

        /// A report.
        ///
        /// - Parameters:
        ///   - id: Its identity.
        ///   - date: When it was taken.
        ///   - note: What the person said.
        ///   - screenshot: The key window.
        ///   - logs: The recent log lines.
        ///   - state: The host's state, or `nil`.
        public init(id: UUID, date: Date, note: String, screenshot: Screenshot, logs: Logs, state: DebugDrawerDiagnosticsCapture.Body?) {
            self.id = id
            self.date = date
            self.note = note
            self.screenshot = screenshot
            self.logs = logs
            self.state = state
        }
    }

    /// A copy of a report a sidecar took into its own bug report, as the app recorded it.
    public struct Export: Codable, Equatable, Sendable {
        /// The report copied.
        public let reportID: UUID
        /// When the sidecar exported it.
        public let date: Date

        /// An export record.
        ///
        /// - Parameters:
        ///   - reportID: The report copied.
        ///   - date: When it was exported.
        public init(reportID: UUID, date: Date) {
            self.reportID = reportID
            self.date = date
        }
    }

    /// What a sidecar sees.
    public struct Snapshot: Codable, Equatable, Sendable {
        /// The session the reports were taken in, or `nil` while there is none.
        public var sessionID: UUID?
        /// The reports kept, oldest first.
        public var reports: [Report]
        /// The copies a sidecar took this session, oldest first.
        public var exports: [Export]
        /// The bounds they keep to.
        public var limits: Limits

        /// A snapshot.
        ///
        /// - Parameters:
        ///   - sessionID: The session the reports were taken in, or `nil`.
        ///   - reports: The reports kept.
        ///   - exports: The session's exports.
        ///   - limits: The bounds.
        public init(sessionID: UUID?, reports: [Report], exports: [Export], limits: Limits) {
            self.sessionID = sessionID
            self.reports = reports
            self.exports = exports
            self.limits = limits
        }
    }

    /// What came of a trigger.
    public enum TriggerResult: Equatable, Sendable {
        /// A report was taken, and the sidecar sees it.
        case captured(Report)
        /// No report was taken, for this reason; ``DebugDrawerAuditEntry/Refusal/noActiveSession``
        /// outside a session.
        case refused(DebugDrawerAuditEntry.Refusal)
    }
}
