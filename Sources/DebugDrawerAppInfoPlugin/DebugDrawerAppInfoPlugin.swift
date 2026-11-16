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

    public struct AppInfoPlugin: DebugDrawerPlugin {
        public var title = "App Info"
        public var category = "App"
        public var icon = "info.circle"

        public init() {}

        public var body: some View {
            AppInfoPluginView()
        }
    }

    struct AppInfoPluginView: View {
        @ObservedObject var metrics = AppMetrics.shared

        var body: some View {
            AppInfoFactsView(facts: AppInfoFacts(metrics: metrics)) { metrics.refresh() }
        }
    }

    /// The facts, in sections, with buttons to copy them and to read them again.
    struct AppInfoFactsView: View {
        let facts: AppInfoFacts
        let refresh: () -> Void
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(facts.sections.enumerated()), id: \.offset) { _, section in
                    ForEach(section, id: \.label) { fact in
                        row(fact)
                    }
                    Divider()
                }

                HStack {
                    Button("Copy Info") { debugDrawerCopyToClipboard(facts.report) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                    Button("Refresh", action: refresh)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }

        // At accessibility text sizes a label no longer fits its column, so it sits above the value.
        private func row(_ fact: AppInfoFacts.Fact) -> some View {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
                : AnyLayout(HStackLayout())
            return layout {
                Text(fact.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: dynamicTypeSize.isAccessibilitySize ? nil : 80, alignment: .leading)
                Text(fact.value)
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
                if !dynamicTypeSize.isAccessibilitySize {
                    Spacer()
                }
            }
            .accessibilityElement(children: .combine)
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
