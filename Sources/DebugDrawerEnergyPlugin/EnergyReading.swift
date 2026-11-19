#if DEBUG
    import DebugDrawer
    import Foundation

    /// What the Energy monitor sampled last, and how each value reads: the view's side of an
    /// ``EnergySnapshot``, with its labels and severities.
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
        let thermalState: EnergyThermalState

        /// The thermal state in a word.
        var thermalLabel: String {
            thermalState.label
        }

        /// The CPU use, bucketed.
        var cpuLoad: String {
            CPULoad(cpuUsage: cpuUsage).label
        }

        /// How heavy the CPU load is: `nil` (the accent) while low or moderate, a warning while
        /// high, an error while very high.
        var cpuLoadSeverity: DebugDrawerIssueGlyph.Severity? {
            switch CPULoad(cpuUsage: cpuUsage) {
            case .low, .moderate: nil
            case .high: .warning
            case .veryHigh: .error
            }
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
            case .unknown: .neutral
            }
        }
    }

    extension EnergyReading {
        /// The reading of what `snapshot` holds.
        ///
        /// - Parameter snapshot: What the monitor sampled.
        init(_ snapshot: EnergySnapshot) {
            self.init(
                cpuUsage: snapshot.cpuUsage,
                cpuHistory: snapshot.cpuHistory,
                batteryLevel: snapshot.batteryLevel,
                batteryHistory: snapshot.batteryHistory.map(\.level),
                isCharging: snapshot.isCharging,
                powerSource: snapshot.powerSource,
                thermalState: snapshot.thermalState
            )
        }
    }
#endif
