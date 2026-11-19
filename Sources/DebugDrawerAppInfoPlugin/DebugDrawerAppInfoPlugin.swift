import DebugDrawer
import SwiftUI

// MARK: - Plugin

// The public API compiles in every configuration; the implementation under `#if DEBUG` below does
// not, so release builds get an empty view and an installer that registers nothing.

/// The App Info plugin: the build (version, commit, branch, CI build), the process, the device,
/// the provisioning profile and the entitlements.
public struct AppInfoPlugin: DebugDrawerPlugin {
    /// The plugin's identity in the drawer, which its saved state, HUD pin and badges are kept under.
    public var id: String {
        "AppInfoPlugin"
    }

    public var title = "App Info"
    public var category = "App"
    public var icon = "info.circle"

    let buildMetadata: AppInfoBuildMetadata

    #if DEBUG
        let signing: AppSigningStore
        /// The metrics the plugin shows and refreshes, or `nil` for ``AppMetrics/shared``, which
        /// is made only once something reads it.
        private let metrics: AppMetrics?

        /// - Parameter buildMetadata: The commit, branch and CI build to show; each one `nil` is
        ///   read from the main bundle's Info.plist (``AppInfoBuildMetadata``).
        @MainActor public init(buildMetadata: AppInfoBuildMetadata = AppInfoBuildMetadata()) {
            self.init(buildMetadata: buildMetadata, signing: .shared)
        }

        /// - Parameters:
        ///   - buildMetadata: The commit, branch and CI build to show.
        ///   - signing: The provisioning profile and entitlements to show.
        ///   - metrics: The metrics to show and refresh in place of the shared ones.
        init(buildMetadata: AppInfoBuildMetadata, signing: AppSigningStore, metrics: AppMetrics? = nil) {
            self.buildMetadata = buildMetadata
            self.signing = signing
            self.metrics = metrics
        }
    #else
        /// - Parameter buildMetadata: The commit, branch and CI build to show; each one `nil` is
        ///   read from the main bundle's Info.plist (``AppInfoBuildMetadata``).
        @MainActor public init(buildMetadata: AppInfoBuildMetadata = AppInfoBuildMetadata()) {
            self.buildMetadata = buildMetadata
        }
    #endif

    public var body: some View {
        #if DEBUG
            AppInfoPluginView(metrics: metrics ?? .shared, buildMetadata: buildMetadata, signing: signing)
        #else
            EmptyView()
        #endif
    }

    /// Reads the memory footprint and uptime now and every 2 seconds after: the plugin's view is
    /// on screen in `drawer`. Release builds read nothing.
    @MainActor public func didBecomeVisible(in drawer: DebugDrawer) {
        #if DEBUG
            (metrics ?? .shared).addViewer()
        #endif
    }

    /// Stops the refreshing ``didBecomeVisible(in:)`` started, once no drawer shows the plugin.
    @MainActor public func didBecomeHidden(in drawer: DebugDrawer) {
        #if DEBUG
            (metrics ?? .shared).removeViewer()
        #endif
    }
}

// MARK: - Convenience installer

public extension DebugDrawer {
    /// Adds the App Info plugin, replacing one added before.
    ///
    /// Nothing is read until the plugin is shown or a report is made.
    ///
    /// - Parameter buildMetadata: The commit, branch and CI build to show; each one `nil` is
    ///   read from the main bundle's Info.plist (``AppInfoBuildMetadata``).
    func installAppInfo(buildMetadata: AppInfoBuildMetadata = AppInfoBuildMetadata()) {
        #if DEBUG
            let plugin = AppInfoPlugin(buildMetadata: buildMetadata)
            unregisterGlobal(id: plugin.id)
            registerGlobal(plugin)
        #endif
    }
}

#if DEBUG
    #if os(macOS)
        import AppKit
    #elseif os(iOS)
        import UIKit
    #endif
    import Combine
    import DebugDrawer
    import Network
    import SwiftUI

    // MARK: - Process start

    /// What the kernel knows about this process's start (`kinfo_proc`).
    struct ProcessStart: Equatable {
        /// When the process started (`kp_proc.p_starttime`).
        var date: Date
        /// A debugger is attached (`P_TRACED` in `kp_proc.p_flag`).
        var isTraced: Bool

        static func current() -> ProcessStart? {
            var mib = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
            var info = kinfo_proc()
            var size = MemoryLayout<kinfo_proc>.size
            guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0 else { return nil }
            let start = info.kp_proc.p_starttime
            guard start.tv_sec > 0 else { return nil }
            return ProcessStart(
                date: Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000),
                isTraced: info.kp_proc.p_flag & P_TRACED != 0
            )
        }
    }

    // MARK: - App metrics

    /// The memory footprint and uptime, refreshed every 2 seconds while a drawer shows the plugin,
    /// and the network's reachability.
    ///
    /// The refresh timer runs from the first drawer showing the plugin to the last. The network
    /// path monitor runs from the shared metrics' first use: it costs nothing between changes,
    /// and the bug report and Copy Info read the network status while the drawer may be closed,
    /// which a monitor started only then would not yet know.
    @MainActor
    final class AppMetrics: ObservableObject {
        static let shared = AppMetrics()

        @Published private(set) var footprintMB: Double = 0
        /// Time since the process started, or nil if the kernel didn't say when that was.
        @Published private(set) var uptime: TimeInterval?
        @Published private(set) var networkStatus: String = "Unknown"

        /// The process's start, read once; nil if `kinfo_proc` couldn't be read.
        let processStart: ProcessStart?

        private let now: () -> Date
        private let timer: any SamplingTimer
        /// The drawers showing the plugin; the timer runs while there is one.
        private var viewers = 0
        private let pathMonitor = NWPathMonitor()

        private convenience init() {
            self.init(processStart: .current(), now: Date.init, timer: RunLoopSamplingTimer(interval: 2))
            startNetworkMonitoring()
        }

        /// - Parameters:
        ///   - processStart: the process's start, from `ProcessStart.current()`.
        ///   - now: the wall clock. Injected in tests.
        ///   - timer: what calls ``refresh()`` while a drawer shows the plugin. Injected in tests.
        init(processStart: ProcessStart?, now: @escaping () -> Date, timer: any SamplingTimer = RunLoopSamplingTimer(interval: 2)) {
            self.processStart = processStart
            self.now = now
            self.timer = timer
            refresh()
        }

        /// Counts a drawer showing the plugin; the first one refreshes now and starts the timer.
        func addViewer() {
            viewers += 1
            guard viewers == 1 else { return }
            refresh()
            timer.start { [weak self] in self?.refresh() }
        }

        /// Uncounts a drawer that showed the plugin; the last one stops the timer.
        func removeViewer() {
            guard viewers > 0 else { return }
            viewers -= 1
            if viewers == 0 { timer.stop() }
        }

        func refresh() {
            footprintMB = MemoryFootprint.currentMB()
            uptime = processStart.map { now().timeIntervalSince($0.date) }
        }

        private func startNetworkMonitoring() {
            pathMonitor.pathUpdateHandler = { [weak self] path in
                let status: String
                if path.status == .satisfied {
                    if path.usesInterfaceType(.wifi) {
                        status = "WiFi"
                    } else if path.usesInterfaceType(.cellular) {
                        status = "Cellular"
                    } else if path.usesInterfaceType(.wiredEthernet) {
                        status = "Ethernet"
                    } else {
                        status = "Online"
                    }
                } else {
                    status = "Offline"
                }
                Task { @MainActor [weak self] in
                    self?.networkStatus = status
                }
            }
            pathMonitor.start(queue: DispatchQueue(label: "com.debugdrawer.network-monitor"))
        }

    }

    /// The facts. Showing it refreshes nothing by itself: the drawer that shows it starts the
    /// metrics' timer through the plugin's lifecycle hooks.
    struct AppInfoPluginView: View {
        @ObservedObject var metrics: AppMetrics
        let buildMetadata: AppInfoBuildMetadata
        let signing: AppSigningStore

        var body: some View {
            AppInfoFactsView(facts: AppInfoFacts(metrics: metrics, buildMetadata: buildMetadata, signing: signing.signing)) {
                metrics.refresh()
            }
        }
    }

    /// The facts, in sections, then the provisioning profile and the entitlements, with buttons
    /// to copy them all and to read them again.
    struct AppInfoFactsView: View {
        let facts: AppInfoFacts
        let refresh: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(facts.sections, id: \.title) { section in
                    DebugDrawerSection(section.title) {
                        ForEach(section.facts, id: \.label) { fact in
                            DebugDrawerKeyValueRow(fact.label, value: fact.value)
                        }
                    }
                }
                AppInfoProvisioningSection(profile: facts.signing.profile, isExpired: facts.isProfileExpired)
                AppInfoEntitlementsSection(entitlements: facts.signing.entitlements)

                DebugDrawerActionRow {
                    DebugDrawerCopyButton("Copy Info") { facts.report }
                    Button("Refresh", action: refresh)
                }
            }
        }
    }

    extension ProcessInfo {
        var machineHardwareName: String {
            var sysinfo = utsname()
            uname(&sysinfo)
            return withUnsafeBytes(of: &sysinfo.machine) { buf in
                String(cString: buf.bindMemory(to: CChar.self).baseAddress!)
            }
        }
    }

#endif
