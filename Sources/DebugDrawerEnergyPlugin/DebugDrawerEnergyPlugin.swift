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
    public nonisolated var id: String {
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
            EnergyPluginView(transport: .direct(to: monitor ?? .shared))
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
