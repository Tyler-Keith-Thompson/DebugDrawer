import Combine
import DebugDrawer
import Foundation
import SwiftUI

// MARK: - Plugin

// The public API compiles in every configuration; the implementation under `#if DEBUG` below does
// not, so release builds get an empty view and an installer that samples and registers nothing.

public struct EnergyPlugin: DebugDrawerPlugin {
    public var title = "Energy"
    public var category = "Performance"
    public var icon = "bolt.fill"

    public init() {}

    public var body: some View {
        #if DEBUG
            EnergyPluginView()
        #else
            EmptyView()
        #endif
    }
}

// MARK: - Convenience installer

public extension DebugDrawer {
    func installEnergy() {
        #if DEBUG
            EnergyMonitor.shared.start()
            registerGlobal(EnergyPlugin())
        #endif
    }
}

// MARK: - Battery snapshot

public extension EnergyMonitor {
    struct BatterySnapshot: Identifiable {
        public let id = UUID()
        public let timestamp: Date
        public let level: Int
        public let isCharging: Bool
    }
}

#if DEBUG
    #if os(macOS)
        import IOKit.ps
    #elseif os(iOS)
        import UIKit
    #endif

    // MARK: - Battery monitoring switch

    /// The platform's battery-monitoring setting, which the host app can see and set too.
    @MainActor
    protocol BatteryMonitoringSwitch: AnyObject {
        var isEnabled: Bool { get set }
    }

    #if os(iOS)
        @MainActor
        final class DeviceBatteryMonitoring: BatteryMonitoringSwitch {
            var isEnabled: Bool {
                get { UIDevice.current.isBatteryMonitoringEnabled }
                set { UIDevice.current.isBatteryMonitoringEnabled = newValue }
            }
        }
    #endif

    // MARK: - Energy monitor

    @MainActor
    public final class EnergyMonitor: ObservableObject {
        public static let shared = EnergyMonitor()

        @Published public private(set) var batteryLevel: Int = -1 // -1 = no battery (desktop Mac)
        @Published public private(set) var isCharging = false
        @Published public private(set) var powerSource = "Unknown"
        @Published public private(set) var thermalState: ProcessInfo.ThermalState = .nominal
        @Published public private(set) var cpuUsage: Double = 0
        @Published public private(set) var isMonitoring = false

        @Published public private(set) var batteryHistory: [BatterySnapshot] = []
        @Published public private(set) var cpuHistory: [Double] = []

        private var cancellable: AnyCancellable?
        private let historySize = 120 // 2 minutes at 1s intervals

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

        init(batteryMonitoring: BatteryMonitoringSwitch?) {
            self.batteryMonitoring = batteryMonitoring
        }

        public func start() {
            guard !isMonitoring else { return }
            isMonitoring = true
            if let batteryMonitoring {
                hostBatteryMonitoring = batteryMonitoring.isEnabled
                batteryMonitoring.isEnabled = true
            }
            sample()

            cancellable = Timer.publish(every: 1, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in self?.sample() }
        }

        public func stop() {
            guard isMonitoring else { return }
            isMonitoring = false
            cancellable?.cancel()
            cancellable = nil
            if let batteryMonitoring, let hostBatteryMonitoring {
                batteryMonitoring.isEnabled = hostBatteryMonitoring
                self.hostBatteryMonitoring = nil
            }
        }

        private func sample() {
            // Battery info
            #if os(macOS)
                let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
                let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as [CFTypeRef]

                if let source = sources.first,
                   let desc = IOPSGetPowerSourceDescription(snapshot, source).takeUnretainedValue() as? [String: Any] {
                    batteryLevel = desc[kIOPSCurrentCapacityKey] as? Int ?? -1
                    isCharging = (desc[kIOPSIsChargingKey] as? Bool) ?? false
                    powerSource = (desc[kIOPSPowerSourceStateKey] as? String) ?? "Unknown"
                } else {
                    batteryLevel = -1
                    powerSource = "AC Power"
                }
            #elseif os(iOS)
                let level = UIDevice.current.batteryLevel
                batteryLevel = level >= 0 ? Int(level * 100) : -1
                let state = UIDevice.current.batteryState
                isCharging = state == .charging || state == .full
                powerSource = isCharging ? "AC Power" : "Battery"
            #endif

            if batteryLevel >= 0 {
                batteryHistory.append(BatterySnapshot(
                    timestamp: Date(), level: batteryLevel, isCharging: isCharging
                ))
                if batteryHistory.count > historySize {
                    batteryHistory.removeFirst()
                }
            }

            // Thermal state
            thermalState = ProcessInfo.processInfo.thermalState

            // CPU usage for this process
            cpuUsage = Self.processCPUUsage()
            cpuHistory.append(cpuUsage)
            if cpuHistory.count > historySize {
                cpuHistory.removeFirst()
            }
        }

        static func processCPUUsage() -> Double {
            var threadList: thread_act_array_t?
            var threadCount: mach_msg_type_number_t = 0

            guard task_threads(mach_task_self_, &threadList, &threadCount) == KERN_SUCCESS,
                  let threads = threadList
            else { return 0 }

            var totalUsage: Double = 0
            for index in 0 ..< Int(threadCount) {
                var info = thread_basic_info()
                var count = mach_msg_type_number_t(MemoryLayout<thread_basic_info_data_t>.size / MemoryLayout<natural_t>.size)
                let result = withUnsafeMutablePointer(to: &info) { ptr in
                    ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                        thread_info(threads[index], thread_flavor_t(THREAD_BASIC_INFO), intPtr, &count)
                    }
                }
                if result == KERN_SUCCESS, info.flags & TH_FLAGS_IDLE == 0 {
                    totalUsage += Double(info.cpu_usage) / Double(TH_USAGE_SCALE) * 100
                }
                // task_threads hands us a send right on each thread; release it.
                mach_port_deallocate(mach_task_self_, threads[index])
            }

            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threads), vm_size_t(Int(threadCount) * MemoryLayout<thread_act_t>.size))
            return totalUsage
        }

        public var thermalLabel: String {
            switch thermalState {
            case .nominal: "Nominal"
            case .fair: "Fair"
            case .serious: "Serious"
            case .critical: "Critical"
            @unknown default: "Unknown"
            }
        }

        /// This process's CPU use, bucketed. It is not Xcode's Energy Impact: that also
        /// weighs GPU, network, location and wakeups, which aren't measured here.
        public var cpuLoad: String {
            if cpuUsage < 5 { return "Low" }
            if cpuUsage < 20 { return "Moderate" }
            if cpuUsage < 50 { return "High" }
            return "Very High"
        }
    }
#else
    // The release stand-in: the same members, nothing sampled behind them, and every value at its start.

    /// Release builds monitor nothing: this stand-in keeps the debug build's members.
    @MainActor
    public final class EnergyMonitor: ObservableObject {
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

#if DEBUG
    struct EnergyPluginView: View {
        @ObservedObject var monitor = EnergyMonitor.shared
        /// The cores CPU use is measured against: the process's threads together can use each.
        var processorCount = ProcessInfo.processInfo.activeProcessorCount

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                DebugDrawerRow("Monitor", isOn: Binding(
                    get: { monitor.isMonitoring },
                    set: { $0 ? monitor.start() : monitor.stop() }
                ))
                if monitor.isMonitoring {
                    DebugDrawerSection("Processor") {
                        // CPU load, not Energy Impact: no energy counters behind it.
                        DebugDrawerKeyValueRow("CPU Load", value: monitor.cpuLoad)
                        DebugDrawerGaugeRow(
                            "CPU",
                            value: "\(monitor.cpuUsage.formatted(.number.precision(.fractionLength(1))))%",
                            fraction: monitor.cpuUsage / Double(100 * max(processorCount, 1)),
                            severity: monitor.cpuLoadSeverity
                        )
                        DebugDrawerSparkline(
                            "CPU history",
                            data: monitor.cpuHistory,
                            range: 0 ... max(100, monitor.cpuHistory.max() ?? 100),
                            severity: monitor.cpuLoadSeverity
                        )
                    }
                    // A desktop Mac has no battery.
                    if monitor.batteryLevel >= 0 {
                        DebugDrawerSection("Battery") {
                            DebugDrawerGaugeRow(
                                monitor.isCharging ? "Charging" : "Battery",
                                value: "\(monitor.batteryLevel)%",
                                fraction: Double(monitor.batteryLevel) / 100,
                                severity: monitor.batterySeverity
                            )
                            DebugDrawerSparkline(
                                "Battery history",
                                data: monitor.batteryHistory.map { Double($0.level) },
                                range: 0 ... 100,
                                severity: monitor.batterySeverity
                            )
                        }
                    }
                    DebugDrawerSection("Device") {
                        DebugDrawerIssueRow("Thermal State", status: monitor.thermalLabel, severity: monitor.thermalSeverity)
                        DebugDrawerKeyValueRow("Power Source", value: monitor.powerSource)
                    }
                }
            }
        }
    }

    extension EnergyMonitor {
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
