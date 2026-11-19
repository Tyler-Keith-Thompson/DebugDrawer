#if DEBUG
    import DebugDrawer
    import Foundation

    extension MetricKitPlugin: DebugDrawerReportContributor {
        /// Adds each kept payload as a JSON file, so a bug report carries what the system measured
        /// before it.
        public func contribute(to report: inout DebugDrawerReport, redaction _: DebugDrawerRedaction) {
            Self.contribute(store.payloads, to: &report)
        }

        /// Adds each of `payloads` as `<kind> <end of its period>.json`, formatted. No payloads add
        /// nothing. Nothing is redacted: a payload holds measurements, the app's version, the
        /// device's model and OS, and stack frames, none of the user's data.
        nonisolated static func contribute(_ payloads: [MetricKitPayload], to report: inout DebugDrawerReport) {
            for payload in payloads {
                report.add(jsonData: payload.formattedJSONData, named: payload.reportName)
            }
        }
    }
#else
    import DebugDrawer

    // The release stand-in: release builds make no reports.
    extension MetricKitPlugin: DebugDrawerReportContributor {
        /// Adds nothing: release builds make no reports.
        public func contribute(to report: inout DebugDrawerReport, redaction: DebugDrawerRedaction) {}
    }
#endif
