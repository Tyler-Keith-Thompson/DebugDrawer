import DebugDrawer
import Foundation

extension AppInfoPlugin: DebugDrawerReportContributor {
    /// Adds the facts the plugin shows, read now, as `app-info.json`. In release builds it adds
    /// nothing.
    public func contribute(to report: inout DebugDrawerReport, redaction: DebugDrawerRedaction) {
        #if DEBUG
            AppMetrics.shared.refresh()
            let facts = AppInfoFacts(metrics: AppMetrics.shared, buildMetadata: buildMetadata, signing: signing.signing)
            Self.contribute(facts, to: &report, redaction: redaction)
        #endif
    }
}

#if DEBUG
    extension AppInfoPlugin {
        /// Adds `facts` as `app-info.json`: an object of each section's title and, under it, an
        /// object of each fact's label and value, a value whose label matches a key pattern masked.
        /// Provisioning and Entitlements are sections like the rest, entitlements by key.
        static func contribute(_ facts: AppInfoFacts, to report: inout DebugDrawerReport, redaction: DebugDrawerRedaction) {
            let object = facts.reportSections.reduce(into: [String: [String: String]]()) { object, section in
                object[section.title] = section.facts.reduce(into: [String: String]()) { values, fact in
                    // Labels are unique within a section; the first wins should two ever share one.
                    if values[fact.label] == nil {
                        values[fact.label] = redaction.redacting(fact.value, forKey: fact.label)
                    }
                }
            }
            // A dictionary of strings always encodes.
            try? report.add(json: object, named: "app-info.json")
        }
    }
#endif
