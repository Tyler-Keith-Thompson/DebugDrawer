#if DEBUG
    import DebugDrawer
    import SwiftUI

    // MARK: - Launch time capture

    /// Launch timing, measured from app-level events so that opening the drawer late
    /// never changes it.
    ///
    /// - Process start comes from the kernel (`kinfo_proc.p_starttime`).
    /// - App init is when `installLaunchTime()` ran (call it from your `App.init` or
    ///   `application(_:didFinishLaunchingWithOptions:)`).
    /// - First frame is the first time the main run loop goes idle after install: by then
    ///   the first frame has been laid out and committed.
    @MainActor
    final class LaunchTimeTracker: ObservableObject {
        static let shared = LaunchTimeTracker()

        /// System uptime (seconds since boot) now. Injected in tests.
        private let clock: () -> TimeInterval

        /// System uptime when the process started, or nil if the kernel didn't say.
        let processStartUptime: TimeInterval?

        /// System uptime when the tracker was created by `installLaunchTime()`.
        let appInitUptime: TimeInterval

        /// System uptime when the first frame was committed.
        @Published private(set) var firstFrameUptime: TimeInterval?

        private var firstFrameObserver: CFRunLoopObserver?

        init(clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
             processStartUptime: TimeInterval? = LaunchTimeTracker.processStartUptimeFromKernel())
        {
            self.clock = clock
            appInitUptime = clock()
            self.processStartUptime = processStartUptime
        }

        /// Records the first frame the first time the main run loop is about to sleep:
        /// layout and the Core Animation commit for the first frame happen before that.
        func observeFirstFrame() {
            guard firstFrameObserver == nil, firstFrameUptime == nil else { return }
            let observer = CFRunLoopObserverCreateWithHandler(
                nil, CFRunLoopActivity.beforeWaiting.rawValue, false, CFIndex.max
            ) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.recordFirstFrame() }
            }
            firstFrameObserver = observer
            CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        }

        func recordFirstFrame() {
            if let observer = firstFrameObserver {
                CFRunLoopObserverInvalidate(observer)
                firstFrameObserver = nil
            }
            guard firstFrameUptime == nil else { return }
            firstFrameUptime = clock()
        }

        // MARK: - Computed times

        /// Process start to app init: dyld, static initializers, and the app's code before install.
        var preMainDuration: TimeInterval? {
            processStartUptime.map { appInitUptime - $0 }
        }

        var appInitToFirstFrame: TimeInterval? {
            firstFrameUptime.map { $0 - appInitUptime }
        }

        var totalLaunchTime: TimeInterval? {
            guard let start = processStartUptime, let frame = firstFrameUptime else { return nil }
            return frame - start
        }

        // MARK: - Process start

        /// The process's start time from `kinfo_proc`, converted to system uptime.
        nonisolated static func processStartUptimeFromKernel() -> TimeInterval? {
            guard let wallStart = processStartWallClock() else { return nil }
            // uptime now - (wall now - wall start) = uptime at process start
            let elapsed = Date().timeIntervalSince1970 - wallStart
            return ProcessInfo.processInfo.systemUptime - elapsed
        }

        /// The process's start time (seconds since 1970) from `kinfo_proc.kp_proc.p_starttime`.
        nonisolated static func processStartWallClock() -> TimeInterval? {
            var mib = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
            var info = kinfo_proc()
            var size = MemoryLayout<kinfo_proc>.size
            guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0 else { return nil }
            let start = info.kp_proc.p_starttime
            guard start.tv_sec > 0 else { return nil }
            return TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000
        }
    }

    // MARK: - Plugin

    public struct LaunchTimePlugin: DebugDrawerPlugin {
        public var title = "Launch Time"
        public var category = "Performance"
        public var icon = "timer"

        public init() {}

        public var body: some View {
            LaunchTimePluginView()
        }
    }

    struct LaunchTimePluginView: View {
        @ObservedObject var tracker = LaunchTimeTracker.shared

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
                    if let preMain = tracker.preMainDuration {
                        timeRow("Pre-main (dyld + static init)", preMain)
                    }
                    if let toFrame = tracker.appInitToFirstFrame {
                        timeRow("App init to first frame", toFrame)
                    }
                }

                Divider()

                // Raw timestamps
                Group {
                    if let start = tracker.processStartUptime {
                        infoRow("Process start", String(format: "%.4fs", start))
                    }
                    infoRow("App init", String(format: "%.4fs", tracker.appInitUptime))
                    if let frame = tracker.firstFrameUptime {
                        infoRow("First frame", String(format: "%.4fs", frame))
                    }
                }

                HStack {
                    Button("Copy") { copyReport() }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                }
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
            if let toFrame = tracker.appInitToFirstFrame {
                report += "App init to first frame: \(String(format: "%.0f ms", toFrame * 1000))\n"
            }
            if let start = tracker.processStartUptime {
                report += "\nProcess start uptime: \(String(format: "%.4fs", start))\n"
            }
            report += "App init uptime: \(String(format: "%.4fs", tracker.appInitUptime))\n"
            if let frame = tracker.firstFrameUptime {
                report += "First frame uptime: \(String(format: "%.4fs", frame))\n"
            }
            debugDrawerCopyToClipboard(report)
        }
    }

    // MARK: - Convenience installer

    public extension DebugDrawer {
        /// Install the launch time plugin. Call it as early as you can (your `App.init` or
        /// `application(_:didFinishLaunchingWithOptions:)`): app init is measured here, and
        /// the first frame is the first time the main run loop goes idle afterwards.
        func installLaunchTime() {
            LaunchTimeTracker.shared.observeFirstFrame()
            registerGlobal(LaunchTimePlugin())
        }
    }
#endif
