#if DEBUG
    import DebugDrawer
    import Foundation

    extension CrashReportsPlugin: DebugDrawerReportContributor {
        /// Adds each kept report as a text file, so a bug report carries the crashes that preceded
        /// it.
        public func contribute(to report: inout DebugDrawerReport, redaction _: DebugDrawerRedaction) {
            Self.contribute(store.reports, to: &report)
        }

        /// Adds each of `reports` as `<title> <date>.txt`, its text with the stack trace. No
        /// reports add nothing. Nothing is redacted: a stack trace names code, not the user's data.
        static func contribute(_ reports: [CrashReport], to report: inout DebugDrawerReport) {
            for crash in reports {
                let date = crash.date.formatted(.iso8601)
                report.add(text: crash.text(), named: "\(crash.title) \(date)")
            }
        }
    }
#else
    import DebugDrawer

    // The release stand-in: release builds make no reports.
    extension CrashReportsPlugin: DebugDrawerReportContributor {
        /// Adds nothing: release builds make no reports.
        public func contribute(to report: inout DebugDrawerReport, redaction: DebugDrawerRedaction) {}
    }
#endif
