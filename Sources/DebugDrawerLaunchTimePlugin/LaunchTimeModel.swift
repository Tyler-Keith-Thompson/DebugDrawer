import Combine
import DebugDrawer
import Foundation

#if DEBUG
    // The times come from app-level events, never from the drawer opening, so opening it late
    // changes nothing. The system work (the kernel's process start, the clock, the main run loop)
    // stays behind `ProcessStartReader`, `UptimeClock` and `FirstFrameObserver`; the model holds
    // values only. A launch happens once, so nothing is stored for the next: a store of past
    // launches would be a new feature, not part of this split.

    /// The Launch Time plugin's state and behavior, without its views: when the process started,
    /// when the app initialized and when the first frame was in, read as a
    /// ``LaunchTimeSnapshot`` and changed with a ``LaunchTimeCommand``.
    ///
    /// The plugin's view reaches it through a `DebugDrawerPluginTransport`:
    ///
    /// ```swift
    /// let transport = DebugDrawerPluginTransport.direct(to: LaunchTimeModel.shared)
    /// ```
    ///
    /// Release builds get a stand-in whose snapshot holds nothing and which ignores every command.
    @MainActor
    public final class LaunchTimeModel: DebugDrawerPluginModel {
        /// The model `installLaunchTime()` makes, so app init is measured there; the plugin
        /// shows it.
        public static let shared = LaunchTimeModel()

        let clock: any UptimeClock
        let firstFrameObserver: any FirstFrameObserver

        /// System uptime when the process started, or `nil` if it couldn't be read.
        let processStartUptime: TimeInterval?
        /// System uptime when the model was made.
        let appInitUptime: TimeInterval
        /// System uptime when the first frame was in.
        @Published private(set) var firstFrameUptime: TimeInterval?

        /// Whether ``firstFrameObserver`` is waiting for the first frame.
        private(set) var isWaitingForFirstFrame = false
        /// The drawers holding the plugin: the last to uninstall it stops the wait.
        private var drawers: Set<ObjectIdentifier> = []

        /// Measures app init as now.
        ///
        /// - Parameters:
        ///   - clock: The system's uptime.
        ///   - processStart: When the process started.
        ///   - firstFrameObserver: Says when the first frame is in.
        init(
            clock: any UptimeClock = _UptimeClock(),
            processStart: any ProcessStartReader = _ProcessStartReader(),
            firstFrameObserver: any FirstFrameObserver = _FirstFrameObserver()
        ) {
            self.clock = clock
            self.firstFrameObserver = firstFrameObserver
            appInitUptime = clock.uptime
            processStartUptime = processStart.processStartUptime()
        }

        public var snapshot: LaunchTimeSnapshot {
            LaunchTimeSnapshot(
                processStartUptime: processStartUptime,
                appInitUptime: appInitUptime,
                firstFrameUptime: firstFrameUptime
            )
        }

        public func perform(_ command: LaunchTimeCommand) {
            switch command.action {
            case .recordFirstFrame: recordFirstFrame()
            }
        }

        /// Counts `drawer` as one holding the plugin, and waits for the first frame.
        func install(in drawer: ObjectIdentifier) {
            drawers.insert(drawer)
            waitForFirstFrame()
        }

        /// Uncounts `drawer`; once no drawer holds the plugin, stops waiting for the first frame.
        /// The times already measured stay: a launch happens once.
        func uninstall(from drawer: ObjectIdentifier) {
            drawers.remove(drawer)
            guard drawers.isEmpty else { return }
            stopWaitingForFirstFrame()
        }

        /// Waits for the first frame, unless one is recorded or the model already waits.
        func waitForFirstFrame() {
            guard !isWaitingForFirstFrame, firstFrameUptime == nil else { return }
            isWaitingForFirstFrame = true
            firstFrameObserver.start { [weak self] in self?.recordFirstFrame() }
        }

        private func stopWaitingForFirstFrame() {
            guard isWaitingForFirstFrame else { return }
            isWaitingForFirstFrame = false
            firstFrameObserver.stop()
        }

        private func recordFirstFrame() {
            stopWaitingForFirstFrame()
            guard firstFrameUptime == nil else { return }
            firstFrameUptime = clock.uptime
        }
    }
#else
    // The release stand-in: the same members, and nothing behind them.

    /// Release builds measure nothing: this stand-in's snapshot holds nothing, and it ignores
    /// every command.
    @MainActor
    public final class LaunchTimeModel: DebugDrawerPluginModel {
        /// The stand-in model.
        public static let shared = LaunchTimeModel()

        private init() {}

        /// Always empty.
        public var snapshot: LaunchTimeSnapshot {
            LaunchTimeSnapshot()
        }

        /// Does nothing.
        ///
        /// - Parameter command: Ignored.
        public func perform(_ command: LaunchTimeCommand) {}
    }
#endif
