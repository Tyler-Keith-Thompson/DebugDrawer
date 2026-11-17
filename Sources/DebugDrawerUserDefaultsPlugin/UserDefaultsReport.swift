#if DEBUG
    import DebugDrawer
    import Foundation

    extension UserDefaultsPlugin: DebugDrawerReportContributor {
        /// Adds the app's own keys in the standard defaults, read now, as `user-defaults.json`.
        public func contribute(to report: inout DebugDrawerReport, redaction: DebugDrawerRedaction) {
            let entries = model.entries(in: .standard).filter { !UserDefaultsModel.isSystemKey($0.key) }
            Self.contribute(entries, to: &report, redaction: redaction)
        }

        /// Adds `entries` as `user-defaults.json`: an object of each key's type and value as the
        /// plugin copies it, a value whose key matches a key pattern masked. No entries add nothing.
        static func contribute(_ entries: [DefaultsEntry], to report: inout DebugDrawerReport, redaction: DebugDrawerRedaction) {
            guard !entries.isEmpty else { return }
            let object = entries.reduce(into: [String: ReportedDefault]()) { object, entry in
                object[entry.key] = ReportedDefault(type: entry.value.type.title, value: entry.copiedValue(redaction: redaction))
            }
            // An object of strings always encodes.
            try? report.add(json: object, named: "user-defaults.json")
        }
    }

    /// One key's entry in `user-defaults.json`.
    private struct ReportedDefault: Encodable {
        var type: String
        var value: String
    }
#endif
