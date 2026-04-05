#if DEBUG
    import DebugDrawer
    import SwiftUI

    // MARK: - Launch time capture

    /// Captures timing data as early as possible.
    ///
    /// The `moduleInitTime` is set at static-init time (before `main()` for Swift).
    /// `firstAppearTime` is set when the plugin view first appears.
    @MainActor
    final class LaunchTimeTracker: ObservableObject {
        static let shared = LaunchTimeTracker()

        /// Approximate time the process started, derived from `ProcessInfo.processInfo.systemUptime`
        /// captured at module init. This is as close to process-start as we can get without
        /// reading `kern.proc` sysctl data.
        let processStartUptime: TimeInterval

        /// System uptime when this module's static initializer ran.
        /// Captured before main() for ObjC-loaded modules, or at first access for pure Swift.
        let moduleInitUptime: TimeInterval

        /// System uptime when the plugin view first appeared.
        @Published var firstAppearUptime: TimeInterval?

        /// Whether the first appear has been recorded.
        @Published var recorded = false

        private init() {
            // Capture as early as possible
            let now = ProcessInfo.processInfo.systemUptime
            self.moduleInitUptime = now

            // Estimate process start from ProcessInfo
            // processInfo.systemUptime is monotonic seconds since boot.
            // We can approximate the process start by reading the process creation time.
            self.processStartUptime = Self.estimateProcessStart() ?? now
        }

        func recordFirstAppear() {
            guard !recorded else { return }
            firstAppearUptime = ProcessInfo.processInfo.systemUptime
            recorded = true
        }

        // MARK: - Computed times

        var preMainDuration: TimeInterval? {
            // Time from process start to module init
            moduleInitUptime - processStartUptime
        }

        var mainToFirstFrame: TimeInterval? {
            guard let appear = firstAppearUptime else { return nil }
            return appear - moduleInitUptime
        }

        var totalLaunchTime: TimeInterval? {
            guard let appear = firstAppearUptime else { return nil }
            return appear - processStartUptime
        }

        // MARK: - Process start estimation

        /// Uses sysctl to get the actual process start time.
        private static func estimateProcessStart() -> TimeInterval? {
            var mib = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
            var info = kinfo_proc()
            var size = MemoryLayout<kinfo_proc>.size

            let result = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
            guard result == 0 else { return nil }

            let startSec = info.kp_proc.p_starttime.tv_sec
            let startUsec = info.kp_proc.p_starttime.tv_usec

            // Convert wall-clock process start to system uptime.
            // wall-clock now - process wall-clock start = elapsed since start
            // system uptime now - elapsed = system uptime at process start
            let now = ProcessInfo.processInfo.systemUptime
            let wallNow = Date().timeIntervalSince1970
            let wallStart = TimeInterval(startSec) + TimeInterval(startUsec) / 1_000_000
            let elapsed = wallNow - wallStart

            return now - elapsed
        }
    }

    // LaunchTimeTracker.shared is initialized lazily on first access.
    // The install() method triggers this.

    // MARK: - Plugin

    public struct LaunchTimePlugin: DebugDrawerPlugin {
        public var title = "Launch Time"
        public var icon = "timer"

        public init() {}

        public var body: some View {
            LaunchTimePluginView()
        }
    }

    private struct LaunchTimePluginView: View {
        @ObservedObject private var tracker = LaunchTimeTracker.shared

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                // Big number: total launch time
                if let total = tracker.totalLaunchTime {
                    HStack(alignment: .firstTextBaseline) {
                        Text(String(format: "%.0f", total * 1000))
                            .font(.system(size: 28, weight: .bold, design: .monospaced))
                            .foregroundStyle(.primary)
                        Text("ms")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Text("Total launch time (process start to first frame)")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                } else {
                    Text("Measuring...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                // Breakdown
                Group {
                    if let preMail = tracker.preMainDuration {
                        timeRow("Pre-main (dyld + static init)", preMail)
                    }
                    if let mainToFrame = tracker.mainToFirstFrame {
                        timeRow("Main to first frame", mainToFrame)
                    }
                }

                Divider()

                // Raw timestamps
                Group {
                    infoRow("Process start", String(format: "%.4fs", tracker.processStartUptime))
                    infoRow("Module init", String(format: "%.4fs", tracker.moduleInitUptime))
                    if let appear = tracker.firstAppearUptime {
                        infoRow("First appear", String(format: "%.4fs", appear))
                    }
                }

                HStack {
                    Button("Copy") { copyReport() }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                }
            }
            .onAppear {
                tracker.recordFirstAppear()
            }
        }

        private func timeRow(_ label: String, _ seconds: TimeInterval) -> some View {
            HStack {
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.0f ms", seconds * 1000))
                    .font(.system(size: 10, design: .monospaced))
                    .fontWeight(.medium)
            }
        }

        private func infoRow(_ label: String, _ value: String) -> some View {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 90, alignment: .leading)
                Text(value)
                    .font(.system(size: 10, design: .monospaced))
                Spacer()
            }
        }

        private func copyReport() {
            var report = "Launch Time Report\n"
            report += String(repeating: "=", count: 30) + "\n"
            if let total = tracker.totalLaunchTime {
                report += "Total: \(String(format: "%.0f ms", total * 1000))\n"
            }
            if let pre = tracker.preMainDuration {
                report += "Pre-main: \(String(format: "%.0f ms", pre * 1000))\n"
            }
            if let main = tracker.mainToFirstFrame {
                report += "Main to first frame: \(String(format: "%.0f ms", main * 1000))\n"
            }
            report += "\nProcess start uptime: \(String(format: "%.4fs", tracker.processStartUptime))\n"
            report += "Module init uptime: \(String(format: "%.4fs", tracker.moduleInitUptime))\n"
            if let appear = tracker.firstAppearUptime {
                report += "First appear uptime: \(String(format: "%.4fs", appear))\n"
            }
            debugDrawerCopyToClipboard(report)
        }
    }

    // MARK: - Convenience installer

    public extension DebugDrawer {
        func installLaunchTime() {
            registerGlobal(LaunchTimePlugin())
        }
    }
#endif
