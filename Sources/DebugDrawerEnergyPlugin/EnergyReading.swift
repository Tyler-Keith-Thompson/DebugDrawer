#if DEBUG
    import DebugDrawer
    import Foundation

    /// What the Energy monitor sampled last, and how each value reads.
    struct EnergyReading: Equatable {
        /// This process's CPU, in percent of one core.
        let cpuUsage: Double
        /// The CPU, one sample a second, oldest first.
        let cpuHistory: [Double]
        /// The battery's charge in percent, or -1 without a battery (a desktop Mac).
        let batteryLevel: Int
        /// The battery's charge, one sample a second, oldest first.
        let batteryHistory: [Int]
        let isCharging: Bool
        let powerSource: String
        let thermalState: ProcessInfo.ThermalState

        /// The thermal state in a word.
        var thermalLabel: String {
            switch thermalState {
            case .nominal: "Nominal"
            case .fair: "Fair"
            case .serious: "Serious"
            case .critical: "Critical"
            @unknown default: "Unknown"
            }
        }

        /// The CPU use, bucketed.
        var cpuLoad: String {
            if cpuUsage < 5 { return "Low" }
            if cpuUsage < 20 { return "Moderate" }
            if cpuUsage < 50 { return "High" }
            return "Very High"
        }

        /// How heavy the CPU load is: `nil` (the accent) while low or moderate, a warning while
        /// high, an error while very high.
        var cpuLoadSeverity: DebugDrawerIssueGlyph.Severity? {
            if cpuUsage < 20 { return nil }
            return cpuUsage < 50 ? .warning : .error
        }

        /// How low the battery is: `nil` while charging or above 20%, a warning to 10%, an error
        /// below.
        var batterySeverity: DebugDrawerIssueGlyph.Severity? {
            if isCharging || batteryLevel > 20 { return nil }
            return batteryLevel > 10 ? .warning : .error
        }

        /// The issue glyph for the thermal state: ok while nominal, a warning while fair or
        /// serious, an error while critical.
        var thermalSeverity: DebugDrawerIssueGlyph.Severity {
            switch thermalState {
            case .nominal: .ok
            case .fair, .serious: .warning
            case .critical: .error
            @unknown default: .neutral
            }
        }
    }
#endif
