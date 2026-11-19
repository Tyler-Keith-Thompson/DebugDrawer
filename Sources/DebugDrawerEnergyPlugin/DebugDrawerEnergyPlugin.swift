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
    /// The plugin's identity in the drawer, which its saved state, HUD pin and badges are kept under.
    public var id: String {
        "EnergyPlugin"
    }

    public var title = "Energy"
    public var category = "Performance"
    public var icon = "bolt.fill"

    #if DEBUG
        /// The monitor the plugin shows and samples with, or `nil` for ``EnergyMonitor/shared``,
        /// which is made only once something reads it.
        private let monitor: EnergyMonitor?

        public init() {
            monitor = nil
        }

        /// - Parameter monitor: The monitor to show and sample with in place of the shared one.
        init(monitor: EnergyMonitor) {
            self.monitor = monitor
        }
    #else
        public init() {}
    #endif

    public var body: some View {
        #if DEBUG
            EnergyPluginView(monitor: monitor ?? .shared)
        #else
            EmptyView()
        #endif
    }

    /// Starts sampling once a second: the plugin's view is on screen in `drawer`. Release builds
    /// sample nothing.
    @MainActor public func didBecomeVisible(in drawer: DebugDrawer) {
        #if DEBUG
            (monitor ?? .shared).addViewer()
        #endif
    }

    /// Stops the sampling ``didBecomeVisible(in:)`` started, once no drawer shows the plugin,
    /// unless the app asked for it with ``EnergyMonitor/start()``.
    @MainActor public func didBecomeHidden(in drawer: DebugDrawer) {
        #if DEBUG
            (monitor ?? .shared).removeViewer()
        #endif
    }

    /// Counts `drawer` as one that holds the plugin; nothing is sampled until it is shown.
    @MainActor public func install(in drawer: DebugDrawer) {
        #if DEBUG
            (monitor ?? .shared).install(in: ObjectIdentifier(drawer))
        #endif
    }

    /// Once the last drawer that held the plugin removes it, stops the sampling the drawers asked
    /// for and, unless the app's ``EnergyMonitor/start()`` keeps it sampling, drops the CPU and
    /// battery history and the last readings.
    @MainActor public func uninstall(from drawer: DebugDrawer) {
        #if DEBUG
            (monitor ?? .shared).uninstall(from: ObjectIdentifier(drawer))
        #endif
    }
}

// MARK: - Convenience installer

public extension DebugDrawer {
    /// Registers the Energy plugin. It samples only while a drawer shows its view, or between the
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
    /// second while a drawer shows the Energy plugin or between ``start()`` and ``stop()``.
    ///
    /// Nothing is recorded from launch unless the app calls ``start()``: the CPU and battery
    /// history keep their last samples while no drawer shows the plugin and carry on from them
    /// when it is shown again.
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

        init(batteryMonitoring: BatteryMonitoringSwitch?, timer: any SamplingTimer = RunLoopSamplingTimer()) {
            self.batteryMonitoring = batteryMonitoring
            self.timer = timer
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
            cpuUsage = 0
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
    /// The monitor's reading. Showing it samples nothing by itself: the drawer that shows it
    /// starts the monitor through the plugin's lifecycle hooks.
    struct EnergyPluginView: View {
        @ObservedObject var monitor = EnergyMonitor.shared
        /// The cores CPU use is measured against: the process's threads together can use each.
        var processorCount = ProcessInfo.processInfo.activeProcessorCount

        var body: some View {
            EnergyReadout(reading: monitor.reading, processorCount: processorCount)
        }
    }
#endif
