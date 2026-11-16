#if DEBUG
    import DebugDrawer
    import Foundation

    extension HangDetectorPlugin: DebugDrawerReportContributor {
        /// Adds the hangs of this run as one text file, so a bug report carries the stalls that
        /// preceded it.
        public func contribute(to report: inout DebugDrawerReport, redaction _: DebugDrawerRedaction) {
            Self.contribute(store.events, threshold: store.threshold, to: &report)
        }

        /// Adds `events`, newest first, each with its stack, as `hangs.txt`, headed by the
        /// threshold. No hangs add nothing. Nothing is redacted: a stack names code, not the
        /// user's data.
        static func contribute(_ events: [HangEvent], threshold: Duration, to report: inout DebugDrawerReport) {
            guard !events.isEmpty else { return }
            let header = "Threshold: \(HangEvent.milliseconds(threshold))\n"
            report.add(text: ([header] + events.map { $0.text() }).joined(separator: "\n"), named: "hangs")
        }
    }
#endif
