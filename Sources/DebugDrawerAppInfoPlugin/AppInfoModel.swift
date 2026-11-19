import Combine
import DebugDrawer
import Foundation

#if DEBUG
    // The system work stays behind plain protocols with real defaults, each in its own file:
    // `BundleInfoSource` (the Info.plist, `_BundleInfoSource`), `DeviceInfoSource` (ProcessInfo,
    // uname and the screen, `_DeviceInfoSource`), `ProcessMetricsSource` (kinfo_proc, the
    // footprint, the PID and arguments, `_ProcessMetricsSource`), `SigningInformation` (the
    // profile and entitlements, `_SigningInformation`), `WallClock` (`_WallClock`),
    // `SamplingTimer` (the 2 s timer, `RunLoopSamplingTimer`) and `NetworkPathWatcher`
    // (`NWPathNetworkWatcher`). The model holds values only, and sets its snapshot once per read,
    // so a view redraws once a tick.

    /// The App Info plugin's state and behavior, without its views: the build, the device, the
    /// process, the network's reachability and the app's signing, read as an ``AppInfoSnapshot``
    /// and changed with an ``AppInfoCommand``.
    ///
    /// Each drawer showing the plugin counts as a viewer, through the plugin's
    /// `didBecomeVisible(in:)` and `didBecomeHidden(in:)`; the facts are read when the first viewer
    /// comes and every 2 seconds until the last goes, and nothing is read before. The network path
    /// is watched from the first drawer installing the plugin to the last removing it: it costs
    /// nothing between changes, and the bug report reads the network status while the drawer may be
    /// closed, which a watcher started only then would not yet know.
    ///
    /// The plugin's view reaches it through a `DebugDrawerPluginTransport`:
    ///
    /// ```swift
    /// let transport = DebugDrawerPluginTransport.direct(to: AppInfoModel.shared)
    /// ```
    ///
    /// Release builds get a stand-in whose snapshot holds nothing and which ignores every command.
    @MainActor
    public final class AppInfoModel: DebugDrawerPluginModel {
        /// The model the plugin shows and refreshes, made the first time something reads it.
        public static let shared = AppInfoModel()

        @Published public private(set) var snapshot = AppInfoSnapshot()

        private let bundle: any BundleInfoSource
        private let device: any DeviceInfoSource
        private let process: any ProcessMetricsSource
        private let signing: AppSigningStore
        private let clock: any WallClock
        private let timer: any SamplingTimer
        private let pathWatcher: any NetworkPathWatcher
        /// The process's start, read the first time the facts are: it can't change.
        private lazy var processStart: ProcessStart? = process.start()
        /// The drawers showing the plugin, and readers that sent `start`; the timer runs while
        /// there is one.
        private var viewers = 0
        /// The drawers the plugin is installed in; the path watcher runs while there is one.
        private var installations: Set<ObjectIdentifier> = []

        private convenience init() {
            self.init(bundle: _BundleInfoSource(), device: _DeviceInfoSource(), process: _ProcessMetricsSource())
        }

        /// A model that reads nothing until a viewer is counted or a refresh is asked for.
        ///
        /// - Parameters:
        ///   - bundle: Reads the bundle's identifier, version and build metadata.
        ///   - device: Reads the device and operating system.
        ///   - process: Reads this process's start, footprint, ID and arguments.
        ///   - signing: Reads the provisioning profile and the entitlements, once.
        ///   - clock: The wall clock the uptime and the profile's expiry are measured against.
        ///   - timer: Reads the facts again every 2 seconds while a drawer shows the plugin.
        ///   - pathWatcher: Reports the network's reachability while a drawer holds the plugin.
        init(
            bundle: any BundleInfoSource,
            device: any DeviceInfoSource,
            process: any ProcessMetricsSource,
            signing: any SigningInformation = _SigningInformation(),
            clock: any WallClock = _WallClock(),
            timer: any SamplingTimer = RunLoopSamplingTimer(interval: 2),
            pathWatcher: any NetworkPathWatcher = NWPathNetworkWatcher()
        ) {
            self.bundle = bundle
            self.device = device
            self.process = process
            self.signing = AppSigningStore(source: signing)
            self.clock = clock
            self.timer = timer
            self.pathWatcher = pathWatcher
        }

        public func perform(_ command: AppInfoCommand) {
            switch command.action {
            case .start: addViewer()
            case .stop: removeViewer()
            case .refresh: refresh()
            }
        }

        /// Counts `drawer` as one the plugin is installed in, showing `buildMetadata` over the
        /// bundle's; the first one starts watching the network path.
        func install(in drawer: ObjectIdentifier, buildMetadata: AppInfoBuildMetadata) {
            if snapshot.buildMetadata != buildMetadata {
                snapshot.buildMetadata = buildMetadata
            }
            guard installations.insert(drawer).inserted, installations.count == 1 else { return }
            pathWatcher.start { [weak self] status in
                Task { @MainActor [weak self] in
                    // A status that arrives after the last uninstall is dropped.
                    guard let self, !self.installations.isEmpty else { return }
                    self.snapshot.network = status
                }
            }
        }

        /// Uncounts `drawer`; once no drawer holds the plugin, stops watching the network path,
        /// forgets its status, and stops the refresh timer should a drawer still count as showing it.
        func uninstall(from drawer: ObjectIdentifier) {
            guard installations.remove(drawer) != nil, installations.isEmpty else { return }
            pathWatcher.stop()
            var next = snapshot
            next.network = .unknown
            if viewers > 0 {
                viewers = 0
                timer.stop()
                next.isSampling = false
            }
            snapshot = next
        }

        /// Counts a drawer showing the plugin; the first one reads the facts now and starts the
        /// timer.
        func addViewer() {
            viewers += 1
            guard viewers == 1 else { return }
            read(isSampling: true)
            timer.start { [weak self] in self?.refresh() }
        }

        /// Uncounts a drawer that showed the plugin; the last one stops the timer.
        func removeViewer() {
            guard viewers > 0 else { return }
            viewers -= 1
            guard viewers == 0 else { return }
            timer.stop()
            snapshot.isSampling = false
        }

        /// Reads every fact now and sets the snapshot once.
        func refresh() {
            read(isSampling: snapshot.isSampling)
        }

        private func read(isSampling: Bool) {
            let now = clock.now
            let signing = self.signing.signing
            var next = snapshot
            next.isSampling = isSampling
            next.bundle = bundle.read()
            next.device = device.read()
            next.processIdentifier = process.processIdentifier
            next.argumentCount = process.argumentCount
            next.processStart = processStart
            next.footprintMB = process.footprintMB()
            next.uptime = processStart.map { now.timeIntervalSince($0.date) }
            next.signing = signing
            next.isProfileExpired = signing.profile.provisioningProfile?.isExpired(at: now) ?? false
            snapshot = next
        }
    }
#else
    // The release stand-in: the same members, and nothing behind them.

    /// Release builds read nothing: this stand-in's snapshot holds nothing, and it ignores every
    /// command.
    @MainActor
    public final class AppInfoModel: DebugDrawerPluginModel {
        /// The stand-in model.
        public static let shared = AppInfoModel()

        private init() {}

        /// Always empty.
        public var snapshot: AppInfoSnapshot {
            AppInfoSnapshot()
        }

        /// Does nothing.
        ///
        /// - Parameter command: Ignored.
        public func perform(_ command: AppInfoCommand) {}
    }
#endif
