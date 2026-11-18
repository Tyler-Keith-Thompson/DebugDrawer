import DebugDrawer
import SwiftUI

// MARK: - Plugin

// The public API compiles in every configuration; the implementation under `#if DEBUG` below does
// not, so release builds get an empty view and an installer that measures and registers nothing.

/// How long the app took to launch: from the process's start to `installLaunchTime()`
/// (pre-main), from there to the first frame, and the total.
public struct LaunchTimePlugin: DebugDrawerPlugin {
    /// The plugin's identity in the drawer, which its saved state, HUD pin and badges are kept under.
    public var id: String {
        "LaunchTimePlugin"
    }

    public var title = "Launch Time"
    public var category = "Performance"
    public var icon = "timer"

    public init() {}

    public var body: some View {
        #if DEBUG
            LaunchTimePluginView()
        #else
            EmptyView()
        #endif
    }
}

// MARK: - Convenience installer

public extension DebugDrawer {
    /// Install the launch time plugin. Call it as early as you can (your `App.init` or
    /// `application(_:didFinishLaunchingWithOptions:)`): app init is measured here, and
    /// the first frame is the first time the main run loop goes idle afterwards.
    func installLaunchTime() {
        #if DEBUG
            LaunchTimeTracker.shared.observeFirstFrame()
            registerGlobal(LaunchTimePlugin())
        #endif
    }
}

#if DEBUG
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
             processStartUptime: TimeInterval? = LaunchTimeTracker.processStartUptimeFromKernel()) {
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

    struct LaunchTimePluginView: View {
        @ObservedObject var tracker = LaunchTimeTracker.shared

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                DebugDrawerSection {
                    if let total = tracker.totalLaunchTime {
                        DebugDrawerKeyValueRow("Total", value: total.milliseconds)
                        // Each phase as its share of the whole launch.
                        if let preMain = tracker.preMainDuration {
                            DebugDrawerGaugeRow("Pre-main", value: preMain.milliseconds, fraction: preMain / max(total, .ulpOfOne))
                        }
                        if let toFrame = tracker.appInitToFirstFrame {
                            DebugDrawerGaugeRow("To frame", value: toFrame.milliseconds, fraction: toFrame / max(total, .ulpOfOne))
                        }
                    } else {
                        DebugDrawerKeyValueRow("Total", value: "Measuring…")
                        if let preMain = tracker.preMainDuration {
                            DebugDrawerKeyValueRow("Pre-main", value: preMain.milliseconds)
                        }
                    }
                } footer: {
                    Text("From process start to the first frame: pre-main is dyld and static initializers, then app init to the first frame.")
                }
                DebugDrawerSection("Uptime") {
                    if let start = tracker.processStartUptime {
                        DebugDrawerKeyValueRow("Process start", value: start.uptime)
                    }
                    DebugDrawerKeyValueRow("App init", value: tracker.appInitUptime.uptime)
                    if let frame = tracker.firstFrameUptime {
                        DebugDrawerKeyValueRow("First frame", value: frame.uptime)
                    }
                }
                DebugDrawerActionRow {
                    DebugDrawerCopyButton("Copy") { report }
                }
            }
        }

        private var report: String {
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
            return report
        }
    }

    extension TimeInterval {
        /// The duration in whole milliseconds ("412 ms").
        fileprivate var milliseconds: String {
            String(format: "%.0f ms", self * 1000)
        }

        /// The system uptime in seconds to a tenth of a millisecond ("100.4000s").
        fileprivate var uptime: String {
            String(format: "%.4fs", self)
        }
    }

#endif
