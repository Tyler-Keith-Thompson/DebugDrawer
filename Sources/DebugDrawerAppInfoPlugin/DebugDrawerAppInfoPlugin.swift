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

        @Published private(set) var memoryMB: Double = 0
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
            memoryMB = Self.currentMemoryMB()
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

        private static func currentMemoryMB() -> Double {
            var info = mach_task_basic_info()
            var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
            let result = withUnsafeMutablePointer(to: &info) { ptr in
                ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                    task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), intPtr, &count)
                }
            }
            guard result == KERN_SUCCESS else { return 0 }
            return Double(info.resident_size) / (1024 * 1024)
        }
    }

    // MARK: - Plugin

    public struct AppInfoPlugin: DebugDrawerPlugin {
        public var title = "App Info"
        public var icon = "info.circle"

        public init() {}

        public var body: some View {
            AppInfoPluginView()
        }
    }

    struct AppInfoPluginView: View {
        @ObservedObject var metrics = AppMetrics.shared

        private let bundle = Bundle.main

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                // Bundle info
                Group {
                    infoRow("Bundle ID", bundle.bundleIdentifier ?? "—")
                    infoRow("Version", "\(bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—") (\(bundle.infoDictionary?["CFBundleVersion"] as? String ?? "—"))")
                    #if os(macOS)
                    infoRow("macOS", ProcessInfo.processInfo.operatingSystemVersionString)
                #elseif os(iOS)
                    infoRow("iOS", ProcessInfo.processInfo.operatingSystemVersionString)
                #endif
                }

                Divider()

                // Runtime
                Group {
                    infoRow("Memory", String(format: "%.1f MB", metrics.memoryMB))
                    infoRow("Uptime", metrics.uptime.map(formatDuration) ?? "—")
                    infoRow("PID", "\(ProcessInfo.processInfo.processIdentifier)")
                    infoRow("Arch", ProcessInfo.processInfo.machineHardwareName)
                    infoRow("Arguments", "\(CommandLine.arguments.count)")
                }

                Divider()

                // Environment
                Group {
                    #if os(macOS)
                        // iOS, tvOS, watchOS and visionOS apps are always sandboxed,
                        // and don't get this variable.
                        infoRow("Sandbox", isSandboxed ? "Yes" : "No")
                    #endif
                    infoRow("Debugger", metrics.processStart.map { $0.isTraced ? "Attached" : "Not attached" } ?? "—")
                    infoRow("Active CPU", "\(ProcessInfo.processInfo.activeProcessorCount)")
                    infoRow("Physical Mem", String(format: "%.0f GB", Double(ProcessInfo.processInfo.physicalMemory) / (1024 * 1024 * 1024)))
                    infoRow("Screen", screenResolution)
                    infoRow("Network", metrics.networkStatus)
                    infoRow("Launched", metrics.processStart.map { Self.launchFormatter.string(from: $0.date) } ?? "—")
                }

                Divider()

                HStack {
                    Button("Copy Info") { copyToClipboard() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                    Button("Refresh") { metrics.refresh() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }

        private func infoRow(_ label: String, _ value: String) -> some View {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .leading)
                Text(value)
                    .font(.system(size: 10, design: .monospaced))
                    .textSelection(.enabled)
                Spacer()
            }
        }

        static let launchFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .medium
            return formatter
        }()

        private func formatDuration(_ seconds: TimeInterval) -> String {
            let h = Int(seconds) / 3600
            let m = (Int(seconds) % 3600) / 60
            let s = Int(seconds) % 60
            if h > 0 { return "\(h)h \(m)m \(s)s" }
            if m > 0 { return "\(m)m \(s)s" }
            return "\(s)s"
        }

        private var isSandboxed: Bool {
            ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
        }

        private var screenResolution: String {
            #if os(macOS)
                guard let screen = NSScreen.main else { return "—" }
                let size = screen.frame.size
                let scale = screen.backingScaleFactor
                return "\(Int(size.width))×\(Int(size.height)) @\(Int(scale))x"
            #elseif os(iOS)
                // The screen of the foreground window scene (UIScreen.main is deprecated).
                let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                guard let screen = (scenes.first { $0.activationState == .foregroundActive } ?? scenes.first)?.screen
                else { return "—" }
                let size = screen.bounds.size
                let scale = screen.scale
                return "\(Int(size.width))×\(Int(size.height)) @\(Int(scale))x"
            #else
                return "—"
            #endif
        }

        private func copyToClipboard() {
            let info = [
                "Bundle: \(bundle.bundleIdentifier ?? "—")",
                "Version: \(bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")",
                "Build: \(bundle.infoDictionary?["CFBundleVersion"] as? String ?? "—")",
                "OS: \(ProcessInfo.processInfo.operatingSystemVersionString)",
                "Memory: \(String(format: "%.1f MB", metrics.memoryMB))",
                "PID: \(ProcessInfo.processInfo.processIdentifier)",
            ].joined(separator: "\n")

            debugDrawerCopyToClipboard(info)
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
        func installAppInfo() {
            registerGlobal(AppInfoPlugin())
        }
    }
#endif
