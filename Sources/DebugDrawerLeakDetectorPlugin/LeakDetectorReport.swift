#if DEBUG
    import DebugDrawer
    import Foundation

    extension LeakDetectorPlugin: DebugDrawerReportContributor {
        /// Adds the suspects as one text file, so a bug report carries what was still alive.
        public func contribute(to report: inout DebugDrawerReport, redaction _: DebugDrawerRedaction) {
            Self.contribute(store.visibleSuspects, to: &report)
        }

        /// Adds `suspects`, in order, as `leaks.txt`. No suspects add nothing. Nothing is redacted:
        /// a class name names code, not the user's data.
        static func contribute(_ suspects: [LeakSuspect], to report: inout DebugDrawerReport) {
            guard !suspects.isEmpty else { return }
            report.add(text: suspects.map { $0.text() }.joined(separator: "\n"), named: "leaks")
        }
    }
#else
    import DebugDrawer

    // The release stand-in: release builds make no reports.
    extension LeakDetectorPlugin: DebugDrawerReportContributor {
        /// Adds nothing: release builds make no reports.
        public func contribute(to report: inout DebugDrawerReport, redaction: DebugDrawerRedaction) {}
    }
#endif
