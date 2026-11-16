#if DEBUG
    import DebugDrawer
    import Foundation

    extension AppInfoPlugin: DebugDrawerReportContributor {
        /// Adds the facts the plugin shows, read now, as `app-info.json`.
        public func contribute(to report: inout DebugDrawerReport, redaction: DebugDrawerRedaction) {
            AppMetrics.shared.refresh()
            Self.contribute(AppInfoFacts(metrics: AppMetrics.shared), to: &report, redaction: redaction)
        }

        /// Adds `facts` as `app-info.json`: an object of each fact's label and value, a value
        /// whose label matches a key pattern masked.
        static func contribute(_ facts: AppInfoFacts, to report: inout DebugDrawerReport, redaction: DebugDrawerRedaction) {
            let object = facts.sections.joined().reduce(into: [String: String]()) { object, fact in
                // Labels are unique; the first wins should two ever share one.
                if object[fact.label] == nil {
                    object[fact.label] = redaction.redacting(fact.value, forKey: fact.label)
                }
            }
            // A dictionary of strings always encodes.
            try? report.add(json: object, named: "app-info.json")
        }
    }
#endif
