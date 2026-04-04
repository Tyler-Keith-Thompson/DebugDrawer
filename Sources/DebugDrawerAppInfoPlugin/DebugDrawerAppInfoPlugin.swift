#if DEBUG
    import AppKit
    import Combine
    import DebugDrawer
    import SwiftUI

    // MARK: - App metrics

    @MainActor
    final class AppMetrics: ObservableObject {
        static let shared = AppMetrics()

        @Published var memoryMB: Double = 0
        @Published var cpuUsage: Double = 0
        @Published var uptime: TimeInterval = 0

        private let startTime = ProcessInfo.processInfo.systemUptime
        private var cancellable: AnyCancellable?

        private init() {
            cancellable = Timer.publish(every: 2, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in self?.refresh() }
            refresh()
        }

        func refresh() {
            memoryMB = Self.currentMemoryMB()
            uptime = ProcessInfo.processInfo.systemUptime - startTime
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
        @ObservedObject private var metrics = AppMetrics.shared

        private let bundle = Bundle.main

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                // Bundle info
                Group {
                    infoRow("Bundle ID", bundle.bundleIdentifier ?? "—")
                    infoRow("Version", "\(bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—") (\(bundle.infoDictionary?["CFBundleVersion"] as? String ?? "—"))")
                    infoRow("macOS", ProcessInfo.processInfo.operatingSystemVersionString)
                }

                Divider()

                // Runtime
                Group {
                    infoRow("Memory", String(format: "%.1f MB", metrics.memoryMB))
                    infoRow("Uptime", formatDuration(metrics.uptime))
                    infoRow("PID", "\(ProcessInfo.processInfo.processIdentifier)")
                    infoRow("Arch", ProcessInfo.processInfo.machineHardwareName)
                    infoRow("Arguments", "\(CommandLine.arguments.count)")
                }

                Divider()

                // Environment
                Group {
                    infoRow("Sandbox", isSandboxed ? "Yes" : "No")
                    infoRow("Debug", "Yes")
                    infoRow("Active CPU", "\(ProcessInfo.processInfo.activeProcessorCount)")
                    infoRow("Physical Mem", String(format: "%.0f GB", Double(ProcessInfo.processInfo.physicalMemory) / (1024 * 1024 * 1024)))
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

        private func copyToClipboard() {
            let info = [
                "Bundle: \(bundle.bundleIdentifier ?? "—")",
                "Version: \(bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")",
                "Build: \(bundle.infoDictionary?["CFBundleVersion"] as? String ?? "—")",
                "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)",
                "Memory: \(String(format: "%.1f MB", metrics.memoryMB))",
                "PID: \(ProcessInfo.processInfo.processIdentifier)",
            ].joined(separator: "\n")

            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(info, forType: .string)
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
