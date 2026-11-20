// The README's "Bug reports from the production app" example, verbatim, so the README cannot drift
// from the code: the app's state, its setup and its own trigger. The test window is never key, so
// the report's screenshot is unavailable; KeyWindowScreenshotTests draws a window of its own.
import DebugDrawerReceiver
import Foundation
import Testing

struct CheckoutState: Encodable {
    let screen: String
    let cartItems: Int
}

@MainActor
private final class ProductionBugReports {
    let sessions = DebugDrawerSessions(maximumDuration: 15 * 60)
    let receiver: DebugDrawerReceiver
    let capture: DebugDrawerDiagnosticsCapture
    let reports: DebugDrawerBugReports

    init(container: URL) throws {
        receiver = DebugDrawerReceiver(directory: container.appending(path: "DebugDrawer"), sessions: sessions)
        capture = DebugDrawerDiagnosticsCapture(sessions: sessions)
        receiver.enable(.diagnosticsCapture(capture))
        let reports = DebugDrawerBugReports(sessions: sessions, diagnostics: capture) {
            CheckoutState(screen: "checkout", cartItems: 2)
        }
        receiver.enable(.bugReports(reports))
        self.reports = reports
        try receiver.start()
    }

    func shaken() {
        let reports = reports
        // The app's own trigger, such as its shake handler:
        reports.trigger(note: "Shaken on the checkout screen")
    }
}

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct BugReportsREADMETests {
    @Test("README: the app's own trigger takes a report in a session, with the note and the app's state")
    func readmeBugReports() throws {
        let container = FileManager.default.temporaryDirectory.appending(path: "READMEBugReports-\(UUID().uuidString)")
        let app = try ProductionBugReports(container: container)
        defer { app.receiver.stop() }
        app.shaken()
        let outside = app.reports.snapshot.reports
        app.sessions.perform(.open(duration: 60))

        app.shaken()

        let report = try #require(app.reports.snapshot.reports.first)
        #expect(outside.isEmpty)
        #expect(app.reports.snapshot.reports.count == 1)
        #expect(report.note == "Shaken on the checkout screen")
        #expect(report.state == .json(#"{"cartItems":2,"screen":"checkout"}"#))
        #expect(report.logs == .notCapturing)
    }
}
