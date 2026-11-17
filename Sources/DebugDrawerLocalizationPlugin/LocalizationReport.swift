#if DEBUG
    import DebugDrawer

    extension LocalizationPlugin: DebugDrawerReportContributor {
        /// Adds `localization.txt`: the mode, Foundation's settings the app launched with, the
        /// languages, and the translations missing for the one the app runs in, so a report about a
        /// wrong string says what the app had.
        public func contribute(to report: inout DebugDrawerReport, redaction _: DebugDrawerRedaction) {
            Self.contribute(mode: model.mode, launchedWith: model.launchedWith, bundles: model.bundles, lookups: model.lookups, to: &report)
        }

        /// Adds `localization.txt`. Keys and development text are the app's own strings, so
        /// nothing is masked.
        static func contribute(
            mode: Localization.Mode, launchedWith: Set<NextLaunchOption>, bundles: [LocalizedBundle], lookups: [LocalizationLookup],
            to report: inout DebugDrawerReport
        ) {
            report.add(text: text(mode: mode, launchedWith: launchedWith, bundles: bundles, lookups: lookups), named: "localization.txt")
        }

        static func text(
            mode: Localization.Mode, launchedWith: Set<NextLaunchOption>, bundles: [LocalizedBundle], lookups: [LocalizationLookup]
        ) -> String {
            var lines = [
                "Mode: \(mode.reportName)",
                "Whole app, from the app's defaults: \(launchedWith.isEmpty ? "off" : launchedWith.summary)",
                "Current language: \(bundles.currentLocalization ?? "unknown")",
                "Development language: \(bundles.developmentLocalization ?? "unknown")",
                "Languages: \(bundles.localizations.isEmpty ? "none" : bundles.localizations.joined(separator: ", "))"
            ]
            if let current = bundles.currentLocalization {
                let missing = MissingTranslation.find(in: bundles, localization: current, lookups: lookups)
                lines.append(missing.isEmpty ? "Missing in \(current): none" : MissingTranslation.text(of: missing, language: current))
            }
            return lines.joined(separator: "\n")
        }
    }

    extension Localization.Mode {
        /// The mode in words.
        fileprivate var reportName: String {
            switch self {
            case .standard: "translations"
            case .pseudoLocalized: "pseudo-localized"
            case .showingKeys: "showing keys"
            }
        }
    }
#endif
