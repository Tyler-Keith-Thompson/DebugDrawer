import Combine
import DebugDrawer
import Foundation

#if DEBUG
    // The monitor is the plugin's model: it was already the one shared store the plugin showed and
    // the app starts and stops (`EnergyMonitor.shared.start()`), so it adopts
    // `DebugDrawerPluginModel` itself rather than sitting behind a second object that would forward
    // every hook and change. Its system work (the battery, the thermal state, Low Power Mode, the
    // process's CPU, the 1 s timer and the time of day) sits behind services it takes at init, each
    // read only while it samples. Labels, severities and gauges are the view's.

    /// The battery, the power source, the thermal state, Low Power Mode and this process's CPU use,
    /// sampled once a second while a drawer shows the Energy plugin or between ``start()`` and
    /// ``stop()``, read as an ``EnergySnapshot`` and changed with an ``EnergyCommand``.
    ///
    /// Nothing is recorded from launch unless the app calls ``start()``: the CPU and battery
    /// history keep their last samples while no drawer shows the plugin and carry on from them
    /// when it is shown again.
    ///
    /// The plugin's view reaches it through a `DebugDrawerPluginTransport`:
    ///
    /// ```swift
    /// let transport = DebugDrawerPluginTransport.direct(to: EnergyMonitor.shared)
    /// ```
    @MainActor
    public final class EnergyMonitor: DebugDrawerPluginModel {
        /// The monitor the Energy plugin shows.
        public static let shared = EnergyMonitor()

        /// The battery's charge in percent, or -1 where there is no battery (a desktop Mac).
        @Published public private(set) var batteryLevel: Int = -1
        /// Whether the battery is charging or full on external power.
        @Published public private(set) var isCharging = false
        /// What powers the device: "AC Power", "Battery Power" on the Mac or "Battery" on iOS, or
        /// "Unknown" before the first sample.
        @Published public private(set) var powerSource = "Unknown"
        /// The system's thermal state.
        @Published public private(set) var thermalState: ProcessInfo.ThermalState = .nominal
        /// This process's CPU use in percent, summed over its threads, so above 100 on several cores.
        @Published public private(set) var cpuUsage: Double = 0
        /// Whether the monitor is sampling.
        @Published public private(set) var isMonitoring = false
        /// Whether Low Power Mode was on at the last reading.
        @Published private(set) var isLowPowerModeEnabled = false

        /// The newest 120 battery samples, two minutes' worth, oldest first.
        @Published public private(set) var batteryHistory: [BatterySnapshot] = []
        /// The newest 120 CPU samples, two minutes' worth, oldest first.
        @Published public private(set) var cpuHistory: [Double] = []

        private let timer: any SamplingTimer
        private let battery: any BatteryReader
        private let thermal: any ThermalStateReader
        private let lowPowerMode: any LowPowerModeReader
        private let cpu: any ProcessCPUReader
        private let clock: any WallClock
        private let historySize = 120 // 2 minutes at 1s intervals
        /// The drawers showing the Energy plugin; sampling runs while there is one, or the app
        /// asked for it.
        private var viewers = 0
        private var isStartedByApp = false
        /// The drawers the Energy plugin is installed in; the last to remove it drops the history.
        private var installations: Set<ObjectIdentifier> = []

        /// Turned on while monitoring (iOS reports no battery level otherwise), then put back.
        private let batteryMonitoring: BatteryMonitoringSwitch?
        private var hostBatteryMonitoring: Bool?

        private convenience init() {
            #if os(iOS)
                self.init(batteryMonitoring: DeviceBatteryMonitoring())
            #else
                self.init(batteryMonitoring: nil)
            #endif
        }

        /// A monitor that samples nothing until asked.
        ///
        /// - Parameters:
        ///   - batteryMonitoring: The platform's battery-monitoring setting, turned on while
        ///     sampling, or `nil` where there is none.
        ///   - timer: Ticks once a second while sampling.
        ///   - battery: The battery and power source.
        ///   - thermal: The thermal state.
        ///   - lowPowerMode: Low Power Mode.
        ///   - cpu: This process's CPU use and the cores it is measured against.
        ///   - clock: The time each battery sample is stamped with.
        init(
            batteryMonitoring: BatteryMonitoringSwitch?,
            timer: any SamplingTimer = RunLoopSamplingTimer(),
            battery: any BatteryReader = _BatteryReader(),
            thermal: any ThermalStateReader = _ThermalStateReader(),
            lowPowerMode: any LowPowerModeReader = _LowPowerModeReader(),
            cpu: any ProcessCPUReader = _ProcessCPUReader(),
            clock: any WallClock = _WallClock()
        ) {
            self.batteryMonitoring = batteryMonitoring
            self.timer = timer
            self.battery = battery
            self.thermal = thermal
            self.lowPowerMode = lowPowerMode
            self.cpu = cpu
            self.clock = clock
        }

        public var snapshot: EnergySnapshot {
            EnergySnapshot(
                isMonitoring: isMonitoring,
                cpuUsage: cpuUsage,
                cpuHistory: cpuHistory,
                processorCount: cpu.processorCount,
                batteryLevel: batteryLevel,
                batteryHistory: batteryHistory.map {
                    BatterySample(timestamp: $0.timestamp, level: $0.level, isCharging: $0.isCharging)
                },
                isCharging: isCharging,
                powerSource: powerSource,
                thermalState: EnergyThermalState(thermalState),
                isLowPowerModeEnabled: isLowPowerModeEnabled
            )
        }

        public func perform(_ command: EnergyCommand) {
            switch command.action {
            case .start: start()
            case .stop: stop()
            case .reset: resetHistory()
            }
        }

        /// Samples once a second until ``stop()``, whether or not a drawer shows the Energy plugin.
        /// The drawer needs no call: the plugin samples while a drawer shows it.
        public func start() {
            isStartedByApp = true
            updateSampling()
        }

        /// Ends what ``start()`` began. Sampling goes on while a drawer shows the Energy plugin.
        public func stop() {
            isStartedByApp = false
            updateSampling()
        }

        /// Counts a drawer showing the Energy plugin; the first one starts sampling.
        func addViewer() {
            viewers += 1
            updateSampling()
        }

        /// Uncounts a drawer that showed the Energy plugin; the last one stops sampling unless the
        /// app started it.
        func removeViewer() {
            guard viewers > 0 else { return }
            viewers -= 1
            updateSampling()
        }

        /// Counts `drawer` as one the Energy plugin is installed in.
        func install(in drawer: ObjectIdentifier) {
            installations.insert(drawer)
        }

        /// Uncounts `drawer`; once no drawer holds the plugin, drops the drawers' demand for
        /// samples and, unless the app's ``start()`` keeps sampling, every reading and its history.
        func uninstall(from drawer: ObjectIdentifier) {
            guard installations.remove(drawer) != nil, installations.isEmpty else { return }
            viewers = 0
            updateSampling()
            guard !isStartedByApp else { return }
            batteryLevel = -1
            isCharging = false
            powerSource = "Unknown"
            thermalState = .nominal
            isLowPowerModeEnabled = false
            cpuUsage = 0
            batteryHistory = []
            cpuHistory = []
        }

        private func resetHistory() {
            batteryHistory = []
            cpuHistory = []
        }

        private func updateSampling() {
            let isWanted = isStartedByApp || viewers > 0
            if isWanted, !isMonitoring { beginSampling() }
            if !isWanted, isMonitoring { endSampling() }
        }

        private func beginSampling() {
            isMonitoring = true
            if let batteryMonitoring {
                hostBatteryMonitoring = batteryMonitoring.isEnabled
                batteryMonitoring.isEnabled = true
            }
            sample()
            timer.start { [weak self] in self?.sample() }
            battery.startObserving { [weak self] in self?.readBattery() }
            thermal.startObserving { [weak self] in self?.readThermalState() }
            lowPowerMode.startObserving { [weak self] in self?.readLowPowerMode() }
        }

        private func endSampling() {
            isMonitoring = false
            timer.stop()
            battery.stopObserving()
            thermal.stopObserving()
            lowPowerMode.stopObserving()
            if let batteryMonitoring, let hostBatteryMonitoring {
                batteryMonitoring.isEnabled = hostBatteryMonitoring
                self.hostBatteryMonitoring = nil
            }
        }

        /// One sample a second: every reading, with the battery and CPU added to their history.
        private func sample() {
            readBattery()
            if batteryLevel >= 0 {
                batteryHistory.append(BatterySnapshot(
                    timestamp: clock.now, level: batteryLevel, isCharging: isCharging
                ))
                if batteryHistory.count > historySize {
                    batteryHistory.removeFirst()
                }
            }

            readThermalState()
            readLowPowerMode()

            cpuUsage = cpu.cpuUsage()
            cpuHistory.append(cpuUsage)
            if cpuHistory.count > historySize {
                cpuHistory.removeFirst()
            }
        }

        private func readBattery() {
            let reading = battery.read()
            batteryLevel = reading.level
            isCharging = reading.isCharging
            powerSource = reading.powerSource
        }

        private func readThermalState() {
            thermalState = thermal.thermalState
        }

        private func readLowPowerMode() {
            isLowPowerModeEnabled = lowPowerMode.isLowPowerModeEnabled
        }

        /// The thermal state in a word.
        public var thermalLabel: String {
            EnergyThermalState(thermalState).label
        }

        /// This process's CPU use, bucketed. It is not Xcode's Energy Impact: that also
        /// weighs GPU, network, location and wakeups, which aren't measured here.
        public var cpuLoad: String {
            CPULoad(cpuUsage: cpuUsage).label
        }
    }
#else
    // The release stand-in: the same members, nothing sampled behind them, and every value at its start.

    /// Release builds monitor nothing: this stand-in keeps the debug build's members.
    @MainActor
    public final class EnergyMonitor: DebugDrawerPluginModel {
        /// The stand-in monitor.
        public static let shared = EnergyMonitor()

        /// Always -1, no battery.
        @Published public private(set) var batteryLevel: Int = -1
        /// Always false.
        @Published public private(set) var isCharging = false
        /// Always "Unknown".
        @Published public private(set) var powerSource = "Unknown"
        /// Always nominal.
        @Published public private(set) var thermalState: ProcessInfo.ThermalState = .nominal
        /// Always zero.
        @Published public private(set) var cpuUsage: Double = 0
        /// Always false.
        @Published public private(set) var isMonitoring = false
        /// Always empty.
        @Published public private(set) var batteryHistory: [BatterySnapshot] = []
        /// Always empty.
        @Published public private(set) var cpuHistory: [Double] = []

        private init() {}

        /// Always empty.
        public var snapshot: EnergySnapshot {
            EnergySnapshot()
        }

        /// Does nothing.
        ///
        /// - Parameter command: Ignored.
        public func perform(_ command: EnergyCommand) {}

        /// Does nothing: release builds sample nothing.
        public func start() {}

        /// Does nothing.
        public func stop() {}

        /// Always "Nominal".
        public var thermalLabel: String {
            "Nominal"
        }

        /// Always "Low".
        public var cpuLoad: String {
            "Low"
        }
    }
#endif
