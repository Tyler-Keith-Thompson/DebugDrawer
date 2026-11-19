#if DEBUG
    // How the thermal state reads in the drawer: formatting, so it sits apart from the snapshot's
    // values, beside the view that shows it.

    extension EnergyThermalState {
        /// The thermal state in a word.
        var label: String {
            switch self {
            case .nominal: "Nominal"
            case .fair: "Fair"
            case .serious: "Serious"
            case .critical: "Critical"
            case .unknown: "Unknown"
            }
        }
    }
#endif
