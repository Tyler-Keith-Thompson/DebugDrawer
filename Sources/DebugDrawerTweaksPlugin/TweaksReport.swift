#if DEBUG
    import DebugDrawer
    import Foundation

    extension TweaksPlugin: DebugDrawerReportContributor {
        /// Adds each tweak's current value as `tweaks.json`, so a report says which settings were on.
        public func contribute(to report: inout DebugDrawerReport, redaction: DebugDrawerRedaction) {
            Self.contribute(sections, stored: TweakStore.shared.storedValue(forKey:), to: &report, redaction: redaction)
        }

        /// Adds `sections`' tweaks as `tweaks.json`: an object of each key's title, the value it
        /// reads as given `stored`, and whether that is its default; a value whose key matches a
        /// key pattern masked. No tweaks add nothing.
        static func contribute(
            _ sections: [TweakSection],
            stored: (String) -> TweakStoredValue?,
            to report: inout DebugDrawerReport,
            redaction: DebugDrawerRedaction
        ) {
            let tweaks = sections.flatMap(\.tweaks)
            guard !tweaks.isEmpty else { return }
            let object = tweaks.reduce(into: [String: ReportedTweak]()) { object, tweak in
                let value = tweak.resolve(stored(tweak.key))
                object[tweak.key] = ReportedTweak(
                    title: tweak.title,
                    value: redaction.redacting(value.description, forKey: tweak.key),
                    isDefault: value == tweak.defaultValue
                )
            }
            // An object of strings and Booleans always encodes.
            try? report.add(json: object, named: "tweaks.json")
        }
    }

    /// One tweak's entry in `tweaks.json`.
    private struct ReportedTweak: Encodable {
        var title: String
        var value: String
        var isDefault: Bool
    }
#endif
