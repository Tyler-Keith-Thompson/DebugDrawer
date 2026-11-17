#if DEBUG
    import DebugDrawer
    import Foundation

    extension FeatureFlagsPlugin: DebugDrawerReportContributor {
        /// Adds each flag's live value, override and the value the app reads as `flags.json`, so a
        /// report says which flags were overridden.
        public func contribute(to report: inout DebugDrawerReport, redaction: DebugDrawerRedaction) {
            Self.contribute(store.rows, to: &report, redaction: redaction)
        }

        /// Adds `rows` as `flags.json`: an object of each key's title, live value, override (absent
        /// when none) and the value the app reads, every value whose key matches a key pattern
        /// masked. No flags add nothing.
        static func contribute(_ rows: [FeatureFlagRowState], to report: inout DebugDrawerReport, redaction: DebugDrawerRedaction) {
            guard !rows.isEmpty else { return }
            let object = rows.reduce(into: [String: ReportedFlag]()) { object, row in
                object[row.id] = ReportedFlag(
                    title: row.title,
                    liveValue: redaction.redacting(row.liveValue.description, forKey: row.id),
                    override: row.override.map { redaction.redacting($0.description, forKey: row.id) },
                    value: redaction.redacting(row.control.value.description, forKey: row.id)
                )
            }
            // An object of strings always encodes.
            try? report.add(json: object, named: "flags.json")
        }
    }

    /// One flag's entry in `flags.json`.
    private struct ReportedFlag: Encodable {
        var title: String
        var liveValue: String
        var override: String?
        /// What the app reads.
        var value: String
    }

    extension FeatureFlagRowState.Control {
        /// The value the control shows.
        fileprivate var value: FeatureFlagValue {
            switch self {
            case let .toggle(isOn): .bool(isOn)
            case let .number(number): .number(number)
            case let .text(text): .string(text)
            }
        }
    }
#else
    import DebugDrawer

    // The release stand-in: release builds make no reports.
    extension FeatureFlagsPlugin: DebugDrawerReportContributor {
        /// Adds nothing: release builds make no reports.
        public func contribute(to report: inout DebugDrawerReport, redaction: DebugDrawerRedaction) {}
    }
#endif
