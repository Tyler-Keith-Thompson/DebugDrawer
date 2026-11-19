import DebugDrawer
import Foundation

extension ConsolePlugin: DebugDrawerReportContributor {
    /// Adds the captured lines the console's filter passes (level, search, mutes and time
    /// range), as Copy All copies them, as `console.txt`, and
    /// every line of the newest session an earlier launch kept as `console-previous.txt`:
    /// after a crash, the lines that led up to it. In release builds it adds nothing.
    public func contribute(to report: inout DebugDrawerReport, redaction: DebugDrawerRedaction) {
        #if DEBUG
            let store = (model ?? .shared).store
            Self.contribute(store.filteredLines, to: &report)
            // Read here, on the main actor, as the report is built now: a session is at most the
            // size limit, 20 MB unless the app set another.
            Self.contribute(previous: store.recorder?.newestPreviousSession(), to: &report)
        #endif
    }
}

#if DEBUG
    extension ConsolePlugin {
        /// Adds `lines` as `console.txt`, one per line in Copy All's format; no lines add nothing.
        /// Log text has no keys for the redaction rules to match, so it goes in as logged.
        nonisolated static func contribute(_ lines: [LogLine], to report: inout DebugDrawerReport) {
            guard !lines.isEmpty else { return }
            report.add(text: lines.copiedText, named: "console.txt")
        }

        /// Adds the lines of `previous`, an earlier launch's session, as `console-previous.txt`,
        /// in Copy All's format, every level included. No session, or one with no lines, adds
        /// nothing.
        nonisolated static func contribute(previous: ConsoleSessionLog?, to report: inout DebugDrawerReport) {
            guard let previous, !previous.lines.isEmpty else { return }
            report.add(text: previous.lines.copiedText, named: "console-previous.txt")
        }
    }

    extension [LogLine] {
        /// The lines as Copy All copies them: time (`HH:mm:ss.SSS`, local), level badge, the
        /// subsystem and category in full (`[com.example.shop/networking]`), text and any metadata
        /// (`order=1042 user=7`), one per line.
        var copiedText: String {
            map { line in
                let time = LogLine.copyDateFormatter.string(from: line.timestamp)
                let badge = line.level.label.map { $0 + " " } ?? ""
                let metadata = line.shownMetadata.map { " " + $0 } ?? ""
                return "\(time) \(badge)\(line.copiedOrigin)\(line.text)\(metadata)"
            }.joined(separator: "\n")
        }
    }

    extension LogLine {
        /// The subsystem and category in brackets, then a space; empty for a line without them.
        fileprivate var copiedOrigin: String {
            switch (subsystem.isEmpty, category.isEmpty) {
            case (true, true): ""
            case (false, true): "[\(subsystem)] "
            case (true, false): "[\(category)] "
            case (false, false): "[\(subsystem)/\(category)] "
            }
        }
    }

    extension LogLine {
        fileprivate static let copyDateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss.SSS"
            return formatter
        }()
    }
#endif
