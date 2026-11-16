#if DEBUG
    import DebugDrawer
    import Foundation

    extension ConsolePlugin: DebugDrawerReportContributor {
        /// Adds the lines the level filter shows, as Copy All copies them, as `console.txt`.
        public func contribute(to report: inout DebugDrawerReport, redaction: DebugDrawerRedaction) {
            Self.contribute(ConsoleLogStore.shared.filteredLines, to: &report)
        }

        /// Adds `lines` as `console.txt`, one per line in Copy All's format; no lines add nothing.
        /// Log text has no keys for the redaction rules to match, so it goes in as logged.
        static func contribute(_ lines: [LogLine], to report: inout DebugDrawerReport) {
            guard !lines.isEmpty else { return }
            report.add(text: lines.copiedText, named: "console.txt")
        }
    }

    extension [LogLine] {
        /// The lines as Copy All copies them: time (`HH:mm:ss.SSS`, local), level badge and text,
        /// one per line.
        var copiedText: String {
            map { line in
                let time = LogLine.copyDateFormatter.string(from: line.timestamp)
                let badge = line.level.label.map { $0 + " " } ?? ""
                return "\(time) \(badge)\(line.text)"
            }.joined(separator: "\n")
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
