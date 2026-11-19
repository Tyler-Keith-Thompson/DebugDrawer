import Foundation

// Public because it is `LaunchTimeModel`'s `Snapshot`, and opaque: its fields stay internal, so a
// reader outside the module carries it whole, encoded. It holds the three moments a launch is
// measured by, as system uptimes; the durations are worked out from them, and the view formats
// both.

#if DEBUG
    /// Everything the Launch Time plugin shows, as a value: when the process started, when the app
    /// initialized (`installLaunchTime()`), and when the first frame was in, each as system uptime.
    ///
    /// ``LaunchTimeModel`` makes it; the plugin's view draws it. It is `Codable`, so a transport
    /// can carry it.
    public struct LaunchTimeSnapshot: Codable, Equatable, Sendable {
        /// System uptime when the process started, or `nil` if the kernel didn't say.
        var processStartUptime: TimeInterval?
        /// System uptime when `installLaunchTime()` made the model.
        var appInitUptime: TimeInterval = 0
        /// System uptime when the first frame was in, or `nil` while still measuring.
        var firstFrameUptime: TimeInterval?

        /// Process start to app init: dyld, static initializers, and the app's code before install.
        var preMainDuration: TimeInterval? {
            processStartUptime.map { appInitUptime - $0 }
        }

        /// App init to the first frame.
        var appInitToFirstFrame: TimeInterval? {
            firstFrameUptime.map { $0 - appInitUptime }
        }

        /// Process start to the first frame.
        var totalLaunchTime: TimeInterval? {
            guard let start = processStartUptime, let frame = firstFrameUptime else { return nil }
            return frame - start
        }
    }
#else
    /// Release builds measure nothing: this stand-in holds nothing.
    public struct LaunchTimeSnapshot: Codable, Equatable, Sendable {}
#endif
