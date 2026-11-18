import Combine
import DebugDrawer
import Foundation
import SwiftUI

// MARK: - Plugin

// The public API compiles in every configuration; the implementation under `#if DEBUG` below does
// not, so release builds get an empty view and an installer that samples and registers nothing.

/// The battery, the power source, the thermal state and this process's CPU load, from
/// ``EnergyMonitor``.
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
    /// Registers the Energy plugin. It samples only while its view is on screen, or between the
    /// app's own ``EnergyMonitor/start()`` and ``EnergyMonitor/stop()``.
    func installEnergy() {
        #if DEBUG
            registerGlobal(EnergyPlugin())
        #endif
    }
}

// MARK: - Battery snapshot

public extension EnergyMonitor {
    /// One battery sample.
    struct BatterySnapshot: Identifiable {
        /// Identifies the sample in a list.
        public let id = UUID()
        /// When it was taken.
        public let timestamp: Date
        /// The charge in percent.
        public let level: Int
        /// Whether the battery was charging.
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

    /// The battery, the power source, the thermal state and this process's CPU use, sampled once a
    /// second while the Energy view is on screen or between ``start()`` and ``stop()``.
    @MainActor
    public final class EnergyMonitor: ObservableObject {
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

        /// The newest 120 battery samples, two minutes' worth, oldest first.
        @Published public private(set) var batteryHistory: [BatterySnapshot] = []
        /// The newest 120 CPU samples, two minutes' worth, oldest first.
        @Published public private(set) var cpuHistory: [Double] = []

        private let timer: any SamplingTimer
        private let historySize = 120 // 2 minutes at 1s intervals
        /// The Energy views on screen; sampling runs while there is one, or the app asked for it.
        private var viewers = 0
        private var isStartedByApp = false

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

        init(batteryMonitoring: BatteryMonitoringSwitch?, timer: any SamplingTimer = RunLoopSamplingTimer()) {
            self.batteryMonitoring = batteryMonitoring
            self.timer = timer
        }

        /// Samples once a second until ``stop()``, whether or not the Energy view is on screen.
        /// The drawer needs no call: its view samples while it is shown.
        public func start() {
            isStartedByApp = true
            updateSampling()
        }

        /// Ends what ``start()`` began. Sampling goes on while the Energy view is on screen.
        public func stop() {
            isStartedByApp = false
            updateSampling()
        }

        /// Counts an Energy view on screen; the first one starts sampling.
        func addViewer() {
            viewers += 1
            updateSampling()
        }

        /// Uncounts an Energy view; the last one stops sampling unless the app started it.
        func removeViewer() {
            guard viewers > 0 else { return }
            viewers -= 1
            updateSampling()
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
        }

        private func endSampling() {
            isMonitoring = false
            timer.stop()
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

        /// The thermal state in a word.
        public var thermalLabel: String {
            reading.thermalLabel
        }

        /// This process's CPU use, bucketed. It is not Xcode's Energy Impact: that also
        /// weighs GPU, network, location and wakeups, which aren't measured here.
        public var cpuLoad: String {
            reading.cpuLoad
        }

        /// The values sampled last, for the view.
        var reading: EnergyReading {
            EnergyReading(
                cpuUsage: cpuUsage,
                cpuHistory: cpuHistory,
                batteryLevel: batteryLevel,
                batteryHistory: batteryHistory.map(\.level),
                isCharging: isCharging,
                powerSource: powerSource,
                thermalState: thermalState
            )
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
            EnergyReadout(reading: monitor.reading, processorCount: processorCount)
                // Sampling runs while the drawer shows this view: closing the drawer, collapsing
                // the section or scrolling it away removes it, which stops it.
                .onAppear { monitor.addViewer() }
                .onDisappear { monitor.removeViewer() }
        }
    }
#endif
