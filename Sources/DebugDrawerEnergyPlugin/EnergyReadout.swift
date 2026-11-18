#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The process's CPU against the device's cores, the battery where there is one, and the
    /// thermal state and power source.
    struct EnergyReadout: View {
        let reading: EnergyReading
        /// The cores CPU use is measured against: the process's threads together can use each.
        let processorCount: Int

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                DebugDrawerSection("Processor") {
                    // CPU load, not Energy Impact: no energy counters behind it.
                    DebugDrawerKeyValueRow("CPU Load", value: reading.cpuLoad)
                    DebugDrawerGaugeRow(
                        "CPU",
                        value: "\(reading.cpuUsage.formatted(.number.precision(.fractionLength(1))))%",
                        fraction: reading.cpuUsage / Double(100 * max(processorCount, 1)),
                        severity: reading.cpuLoadSeverity
                    )
                    DebugDrawerSparkline(
                        "CPU history",
                        data: reading.cpuHistory,
                        range: 0 ... max(100, reading.cpuHistory.max() ?? 100),
                        severity: reading.cpuLoadSeverity
                    )
                }
                // A desktop Mac has no battery.
                if reading.batteryLevel >= 0 {
                    DebugDrawerSection("Battery") {
                        DebugDrawerGaugeRow(
                            reading.isCharging ? "Charging" : "Battery",
                            value: "\(reading.batteryLevel)%",
                            fraction: Double(reading.batteryLevel) / 100,
                            severity: reading.batterySeverity
                        )
                        DebugDrawerSparkline(
                            "Battery history",
                            data: reading.batteryHistory.map(Double.init),
                            range: 0 ... 100,
                            severity: reading.batterySeverity
                        )
                    }
                }
                DebugDrawerSection("Device") {
                    DebugDrawerIssueRow("Thermal State", status: reading.thermalLabel, severity: reading.thermalSeverity)
                    DebugDrawerKeyValueRow("Power Source", value: reading.powerSource)
                }
            }
        }
    }
#endif
