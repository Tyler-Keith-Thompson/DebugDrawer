#if DEBUG
    import DebugDrawer
    import Foundation

    extension AnalyticsPlugin: DebugDrawerReportContributor {
        /// Adds `analytics.json`, every event kept, so a bug report carries what the app sent
        /// before it.
        public func contribute(to report: inout DebugDrawerReport, redaction: DebugDrawerRedaction) {
            Self.contribute(model.events, redaction: redaction, to: &report)
        }

        /// Adds `analytics.json`: `events` as a JSON array, the newest first, with what
        /// `redaction` calls sensitive masked. No events add nothing.
        nonisolated static func contribute(_ events: [AnalyticsEvent], redaction: DebugDrawerRedaction, to report: inout DebugDrawerReport) {
            guard !events.isEmpty else { return }
            report.add(jsonData: Data(AnalyticsEvent.formattedJSON(of: events, redaction: redaction).utf8), named: "analytics")
        }
    }
#else
    import DebugDrawer

    // The release stand-in: release builds make no reports.
    extension AnalyticsPlugin: DebugDrawerReportContributor {
        /// Adds nothing: release builds make no reports.
        public func contribute(to report: inout DebugDrawerReport, redaction: DebugDrawerRedaction) {}
    }
#endif
