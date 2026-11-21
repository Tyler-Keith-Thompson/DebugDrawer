import DebugDrawer
import Foundation
import SwiftUI

// The sidecar's half of dogfood bug reporting (DD-113): the reports the app took as the employee
// triggered them (`DebugDrawerBugReports`, in the receiver), shown with their screenshot, note,
// logs and state, an annotation the employee types for each, and the one to send picked. It is a
// `DebugDrawerReportContributor`, so the kit's Create Report puts the picked report in the bug
// report beside the other plugins' files, and Send Report sends it through the sidecar's uploader
// (`DebugDrawer.shared.reportUploader`), as for every other report: the app never sends anything.
// It ships in the kit beside Console and Network, as every capability's plugin does, and the report
// and its upload are the kit's own.
//
// The annotations and the pick live in an object the plugin holds, not in a view's state, as the
// report is written from the plugin, outside any view. Rejected: drawing on the screenshot (a
// markup editor is a tool of its own, and the annotation already says what to look at), and
// sending each report on its own from this plugin (a second upload path beside the kit's).

#if DEBUG
    extension DebugDrawerSidecarPlugin {
        /// The bug reports the app takes as an employee triggers them during the session
        /// (`DebugDrawerReceiverCapability.bugReports(_:)`): each one's screenshot, note, log lines
        /// and state, with an annotation the employee adds. Create Report puts the report picked in
        /// the bug report, with the annotation, and Send Report sends it through the sidecar's
        /// uploader.
        @MainActor public static var bugReports: DebugDrawerSidecarPlugin {
            DebugDrawerSidecarPlugin(
                id: DebugDrawerBugReports.pluginID, title: "Bug Reports", icon: "ladybug",
                snapshot: DebugDrawerBugReports.Snapshot.self, command: DebugDrawerBugReports.Command.self
            ) { transport in
                BugReportsPlugin(transport: transport, review: BugReportReview())
            }
        }
    }

    /// What the employee added to the app's reports: an annotation for each, and the one to send.
    @MainActor
    final class BugReportReview: ObservableObject {
        /// The annotations, by report.
        @Published var annotations: [UUID: String] = [:]
        /// The report the bug report takes; the newest when none was picked or the one picked is gone.
        @Published var picked: UUID?

        /// The report to put in the bug report, of `reports`.
        func report(of reports: [DebugDrawerBugReports.Report]) -> DebugDrawerBugReports.Report? {
            reports.first { $0.id == picked } ?? reports.last
        }
    }

    /// The app's bug reports, annotated and picked in the sidecar.
    struct BugReportsPlugin: DebugDrawerPlugin, DebugDrawerReportContributor {
        let transport: DebugDrawerPluginTransport<DebugDrawerBugReports.Snapshot, DebugDrawerBugReports.Command>
        let review: BugReportReview
        let title = "Bug Reports"
        let icon = "ladybug"

        var body: some View {
            BugReportsView(transport: transport, review: review)
        }

        /// Adds the picked report, as the app took it and redacted it, with the employee's
        /// annotation: `screenshot.png`, `note.txt`, `console.txt` and `state.json`, each when the
        /// report has it. Then tells the app, which records the export and audits it; the app's copy
        /// is still deleted as the session ends.
        func contribute(to report: inout DebugDrawerReport, redaction: DebugDrawerRedaction) {
            guard let taken = review.report(of: transport.snapshot.reports) else { return }
            if case let .png(data) = taken.screenshot {
                report.add(png: data, named: "screenshot")
            }
            report.add(text: taken.reportNote(annotation: review.annotations[taken.id] ?? ""), named: "note")
            if case .captured = taken.logs {
                report.add(text: taken.logs.consoleLog, named: "console")
            }
            if case let .json(text) = taken.state {
                report.add(jsonData: Data(text.utf8), named: "state")
            }
            transport.send(.export(id: taken.id))
        }
    }

    extension DebugDrawerBugReports.Report {
        /// `note.txt`: when it was taken, the app's note, the employee's annotation, and what was
        /// left out.
        func reportNote(annotation: String) -> String {
            var lines = [
                "Taken: \(date.ISO8601Format())",
                "Note: \(note.isEmpty ? "None" : note)",
                "Annotation: \(annotation.isEmpty ? "None" : annotation)",
                "Screenshot: \(screenshot.summary)",
                "Logs: \(logs.summary)"
            ]
            lines.append("State: \(state?.summary ?? "None given")")
            return lines.joined(separator: "\n")
        }
    }

    extension DebugDrawerBugReports.Screenshot {
        /// Whether there is one, or why not.
        var summary: String {
            switch self {
            case .png: "Attached"
            case .unavailable: "No window to draw"
            case let .tooLarge(byteCount): "Left out, \(byteCount.formatted(.byteCount(style: .file)))"
            }
        }
    }

    extension DebugDrawerBugReports.Logs {
        /// How many lines, or why none.
        var summary: String {
            switch self {
            case let .captured(lines): "\(lines.count) line\(lines.count == 1 ? "" : "s")"
            case .notCapturing: "Not captured"
            }
        }
    }

    extension DebugDrawerDiagnosticsCapture.Body {
        /// Whether it was kept, or why not.
        var summary: String {
            switch self {
            case let .json(text): "\(text.utf8.count.formatted(.byteCount(style: .file))) of JSON"
            case let .omitted(.notJSON, byteCount): "Left out, not JSON (\(byteCount.formatted(.byteCount(style: .file))))"
            case let .omitted(.tooLarge, byteCount): "Left out, \(byteCount.formatted(.byteCount(style: .file)))"
            }
        }
    }

    /// Each report, newest first: its screenshot, what it holds, an annotation, Include in Report and
    /// Delete from App.
    struct BugReportsView: View {
        @ObservedObject var transport: DebugDrawerPluginTransport<DebugDrawerBugReports.Snapshot, DebugDrawerBugReports.Command>
        @ObservedObject var review: BugReportReview

        var body: some View {
            let reports = transport.snapshot.reports
            if reports.isEmpty {
                DebugDrawerEmptyState("No Bug Reports", systemImage: "ladybug") {
                    Text(
                        "A report the app takes through its own trigger during this session appears here. "
                            + "Start the Diagnostics capture first to include its logs."
                    )
                }
            } else {
                let included = review.report(of: reports)?.id
                ForEach(reports.reversed()) { report in
                    BugReportSection(
                        report: report,
                        isIncluded: report.id == included,
                        annotation: Binding { review.annotations[report.id] ?? "" } set: { review.annotations[report.id] = $0 },
                        include: { review.picked = report.id },
                        delete: { transport.send(.delete(id: report.id)) }
                    )
                }
            }
        }
    }

    /// One report: a function of the report, the annotation's binding and the actions.
    struct BugReportSection: View {
        let report: DebugDrawerBugReports.Report
        let isIncluded: Bool
        @Binding var annotation: String
        let include: () -> Void
        let delete: () -> Void

        var body: some View {
            DebugDrawerSection(report.date.formatted(date: .abbreviated, time: .standard)) {
                if case let .png(data) = report.screenshot {
                    BugReportScreenshot(png: data)
                }
                DebugDrawerKeyValueRow("Note", value: report.note.isEmpty ? "None" : report.note)
                DebugDrawerKeyValueRow("Screenshot", value: report.screenshot.summary)
                DebugDrawerKeyValueRow("Logs", value: report.logs.summary)
                DebugDrawerKeyValueRow("State", value: report.state?.summary ?? "None given")
                TextField("Annotation", text: $annotation, axis: .vertical)
                    .debugDrawerTextFieldStyle()
                    .accessibilityLabel("Annotation")
                    .debugDrawerRowPadding()
                DebugDrawerActionRow {
                    if isIncluded {
                        Label("In the Report", systemImage: "checkmark.circle.fill")
                            .debugDrawerFont(.label)
                    } else {
                        Button("Include in Report", action: include)
                            .debugDrawerButtonStyle(.secondary)
                    }
                } trailing: {
                    Button("Delete from App", role: .destructive, action: delete)
                        .debugDrawerButtonStyle(.destructive)
                }
            }
        }
    }

    /// A report's screenshot, scaled to fit; nothing when the PNG doesn't decode.
    struct BugReportScreenshot: View {
        let png: Data

        var body: some View {
            #if os(macOS)
                if let decoded = NSImage(data: png) {
                    Image(nsImage: decoded)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 320)
                        .accessibilityLabel("Screenshot of the app")
                }
            #else
                if let decoded = UIImage(data: png) {
                    Image(uiImage: decoded)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 320)
                        .accessibilityLabel("Screenshot of the app")
                }
            #endif
        }
    }
#else
    // The release stand-in: the same member, over a plugin that draws nothing; a release build's
    // transports connect to nothing anyway.

    extension DebugDrawerSidecarPlugin {
        /// The bug reports the app takes as an employee triggers them; release builds show nothing.
        @MainActor public static var bugReports: DebugDrawerSidecarPlugin {
            DebugDrawerSidecarPlugin(
                id: DebugDrawerBugReports.pluginID, title: "Bug Reports", icon: "ladybug",
                snapshot: DebugDrawerBugReports.Snapshot.self, command: DebugDrawerBugReports.Command.self
            ) { _ in
                BugReportsPlugin()
            }
        }
    }

    /// Draws nothing.
    struct BugReportsPlugin: DebugDrawerPlugin {
        let title = "Bug Reports"
        let icon = "ladybug"

        var body: some View {
            EmptyView()
        }
    }
#endif
