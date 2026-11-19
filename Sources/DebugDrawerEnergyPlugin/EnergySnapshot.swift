import Foundation

// Public because it is `EnergyMonitor`'s `Snapshot`, and opaque: its fields stay internal, so a
// reader outside the module carries it whole, encoded. It holds values only: the thermal state
// and the CPU load are the plugin's own enums, and the labels, severities and gauges are the
// view's. The processor count travels with it, since a reader elsewhere runs on other cores.

#if DEBUG
    /// Everything the Energy plugin shows, as a value: this process's CPU use and its history, the
    /// battery and its history, what powers the device, the thermal state and Low Power Mode, and
    /// whether the monitor is sampling.
    ///
    /// ``EnergyMonitor`` makes it; the plugin's view draws it. It is `Codable`, so a transport can
    /// carry it.
    public struct EnergySnapshot: Codable, Equatable, Sendable {
        /// Whether the monitor is sampling.
        var isMonitoring = false
        /// This process's CPU use in percent of one core, summed over its threads.
        var cpuUsage: Double = 0
        /// The newest CPU samples, one a second, oldest first.
        var cpuHistory: [Double] = []
        /// The cores the process's threads can use together.
        var processorCount = 1
        /// The battery's charge in percent, or -1 where there is no battery.
        var batteryLevel = -1
        /// The newest battery samples, one a second, oldest first.
        var batteryHistory: [BatterySample] = []
        /// Whether the battery is charging or full on external power.
        var isCharging = false
        /// What powers the device, in the platform's words, or "Unknown" before the first sample.
        var powerSource = "Unknown"
        /// The system's thermal state.
        var thermalState = EnergyThermalState.nominal
        /// Whether Low Power Mode is on.
        var isLowPowerModeEnabled = false

        /// How heavy the CPU use is.
        var cpuLoad: CPULoad {
            CPULoad(cpuUsage: cpuUsage)
        }
    }
#else
    /// Release builds sample nothing: this stand-in holds nothing.
    public struct EnergySnapshot: Codable, Equatable, Sendable {}
#endif
