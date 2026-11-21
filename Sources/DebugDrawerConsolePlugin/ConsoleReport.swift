import DebugDrawer
import Foundation

extension ConsolePlugin: DebugDrawerReportContributor {
    /// Adds the captured lines the console's filter passes (level, search, mutes and time
    /// range), as Copy All copies them, as `console.txt`, and
    /// every line of the newest session an earlier launch kept as `console-previous.txt`:
    /// after a crash, the lines that led up to it. A plugin over a transport adds the lines of
    /// its latest snapshot that the filter passes, as `console.txt`. Both are masked by
    /// `redaction`: a metadata field whose key contains a key pattern, and the value of each such
    /// `key=value` or `key: value` pair in a line's text (``DebugDrawerRedaction/redacting(text:)``).
    /// In release builds it adds nothing.
    public func contribute(to report: inout DebugDrawerReport, redaction: DebugDrawerRedaction) {
        #if DEBUG
            if let transport {
                Self.contribute(transport.snapshot.log.filteredLines, redaction: redaction, to: &report)
                return
            }
            let store = (model ?? .shared).store
            Self.contribute(store.filteredLines, redaction: redaction, to: &report)
            // Read here, on the main actor, as the report is built now: a session is at most the
            // size limit, 20 MB unless the app set another.
            Self.contribute(previous: store.recorder?.newestPreviousSession(), redaction: redaction, to: &report)
        #endif
    }
}

#if DEBUG
    extension ConsolePlugin {
        /// Adds `lines` as `console.txt`, one per line in Copy All's format, masked by
        /// `redaction`; no lines add nothing.
        nonisolated static func contribute(_ lines: [LogLine], redaction: DebugDrawerRedaction, to report: inout DebugDrawerReport) {
            guard !lines.isEmpty else { return }
            report.add(text: lines.copiedText(redactedBy: redaction), named: "console.txt")
        }

        /// Adds the lines of `previous`, an earlier launch's session, as `console-previous.txt`,
        /// in Copy All's format, every level included, masked by `redaction`. No session, or one
        /// with no lines, adds nothing.
        nonisolated static func contribute(
            previous: ConsoleSessionLog?, redaction: DebugDrawerRedaction, to report: inout DebugDrawerReport
        ) {
            guard let previous, !previous.lines.isEmpty else { return }
            report.add(text: previous.lines.copiedText(redactedBy: redaction), named: "console-previous.txt")
        }
    }

    extension [LogLine] {
        /// The lines as Copy All copies them, one per line, each as
        /// ``LogLine/copiedText(redactedBy:)`` writes it.
        ///
        /// - Complexity: O(*n*) in the lines' total length.
        func copiedText(redactedBy redaction: DebugDrawerRedaction) -> String {
            map { $0.copiedText(redactedBy: redaction) }.joined(separator: "\n")
        }
    }

    extension LogLine {
        /// The line as Copy All, Copy Line and the report copy it: time (`HH:mm:ss.SSS`, local),
        /// level badge, the subsystem and category in full (`[com.example.shop/networking]`), text
        /// and any metadata (`order=1042 user=7`). A metadata field whose key contains one of
        /// `redaction`'s key patterns is masked, and so is the value of each such `key=value` or
        /// `key: value` pair in the text and in the other fields' values.
        func copiedText(redactedBy redaction: DebugDrawerRedaction) -> String {
            let time = LogLine.copyDateFormatter.string(from: timestamp)
            let badge = level.label.map { $0 + " " } ?? ""
            let metadata = copiedMetadata(redactedBy: redaction).map { " " + $0 } ?? ""
            return "\(time) \(badge)\(copiedOrigin)\(redaction.redacting(text: text))\(metadata)"
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
