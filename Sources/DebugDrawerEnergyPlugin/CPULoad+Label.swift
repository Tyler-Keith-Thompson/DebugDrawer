#if DEBUG
    // How the CPU load reads in the drawer: formatting, so it sits apart from the snapshot's
    // values, beside the view that shows it.

    extension CPULoad {
        /// The load in a word or two.
        var label: String {
            switch self {
            case .low: "Low"
            case .moderate: "Moderate"
            case .high: "High"
            case .veryHigh: "Very High"
            }
        }
    }
#endif
