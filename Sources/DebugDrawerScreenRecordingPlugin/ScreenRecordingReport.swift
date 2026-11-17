#if DEBUG
    import DebugDrawer
    import Foundation

    extension ScreenRecordingPlugin: DebugDrawerReportContributor {
        /// Adds each recording marked In Bug Report (the newest, unless the developer changed
        /// that) as a `.mov`; a recording still in progress isn't one of them.
        public func contribute(to report: inout DebugDrawerReport, redaction _: DebugDrawerRedaction) {
            Self.contribute(model.reportRecordings, to: &report)
        }

        /// Adds each of `recordings` under its file's name, mapped rather than read into memory;
        /// one whose file has gone is skipped, and none adds nothing.
        static func contribute(_ recordings: [Recording], to report: inout DebugDrawerReport) {
            for recording in recordings {
                guard let movie = try? Data(contentsOf: recording.url, options: .alwaysMapped) else { continue }
                report.add(movie: movie, named: recording.url.lastPathComponent)
            }
        }
    }
#else
    import DebugDrawer

    // The release stand-in: release builds make no reports.
    extension ScreenRecordingPlugin: DebugDrawerReportContributor {
        /// Adds nothing: release builds make no reports.
        public func contribute(to report: inout DebugDrawerReport, redaction: DebugDrawerRedaction) {}
    }
#endif
