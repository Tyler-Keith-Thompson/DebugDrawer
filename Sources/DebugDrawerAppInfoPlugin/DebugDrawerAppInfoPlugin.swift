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
        private var cancellable: AnyCancellable?
        private let pathMonitor = NWPathMonitor()

        private convenience init() {
            self.init(processStart: .current(), now: Date.init)
            cancellable = Timer.publish(every: 2, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in self?.refresh() }
            startNetworkMonitoring()
        }

        /// - Parameters:
        ///   - processStart: the process's start, from `ProcessStart.current()`.
        ///   - now: the wall clock. Injected in tests.
        init(processStart: ProcessStart?, now: @escaping () -> Date) {
            self.processStart = processStart
            self.now = now
            refresh()
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

    // MARK: - Plugin

    /// The App Info plugin: the build (version, commit, branch, CI build), the process, the device,
    /// the provisioning profile and the entitlements.
    public struct AppInfoPlugin: DebugDrawerPlugin {
        public var title = "App Info"
        public var category = "App"
        public var icon = "info.circle"

        let buildMetadata: AppInfoBuildMetadata
        let signing: AppSigningStore

        /// - Parameter buildMetadata: The commit, branch and CI build to show; each one `nil` is
        ///   read from the main bundle's Info.plist (``AppInfoBuildMetadata``).
        @MainActor public init(buildMetadata: AppInfoBuildMetadata = AppInfoBuildMetadata()) {
            self.init(buildMetadata: buildMetadata, signing: .shared)
        }

        init(buildMetadata: AppInfoBuildMetadata, signing: AppSigningStore) {
            self.buildMetadata = buildMetadata
            self.signing = signing
        }

        public var body: some View {
            AppInfoPluginView(buildMetadata: buildMetadata, signing: signing)
        }
    }

    struct AppInfoPluginView: View {
        @ObservedObject var metrics = AppMetrics.shared
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

    // MARK: - Convenience installer

    public extension DebugDrawer {
        /// Adds the App Info plugin, replacing one added before.
        ///
        /// Nothing is read until the plugin is shown or a report is made.
        ///
        /// - Parameter buildMetadata: The commit, branch and CI build to show; each one `nil` is
        ///   read from the main bundle's Info.plist (``AppInfoBuildMetadata``).
        func installAppInfo(buildMetadata: AppInfoBuildMetadata = AppInfoBuildMetadata()) {
            let plugin = AppInfoPlugin(buildMetadata: buildMetadata)
            unregisterGlobal(id: plugin.id)
            registerGlobal(plugin)
        }
    }
#endif
