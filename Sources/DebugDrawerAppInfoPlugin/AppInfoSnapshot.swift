import Foundation

// Public because it is `AppInfoModel`'s `Snapshot`, and opaque: its fields stay internal, so a
// reader outside the module carries it whole, encoded. It holds what was read as values (bytes,
// megabytes, seconds, dates, the platform's name, a reachability case); every row's wording,
// unit, date format and the Copy Info text are the view's (`AppInfoFacts`).

#if DEBUG
    /// Everything the App Info plugin shows, as a value: the bundle and the build metadata the
    /// host passed, the device and operating system, this process (its ID, arguments, start,
    /// memory footprint and uptime), the network's reachability, and how the app was signed.
    ///
    /// ``AppInfoModel`` makes it; the plugin's view draws it. It is `Codable`, so a transport can
    /// carry it.
    public struct AppInfoSnapshot: Codable, Equatable, Sendable {
        /// Whether the model is refreshing every 2 seconds: while at least one drawer shows it.
        var isSampling = false
        /// What the bundle's Info.plist says.
        var bundle = BundleInfo()
        /// The commit, branch and CI build the host passed when it installed the plugin; each
        /// `nil` falls back to the bundle's.
        var buildMetadata = AppInfoBuildMetadata()
        /// The device and operating system.
        var device = DeviceInfo()
        /// The process's ID; 0 until read.
        var processIdentifier: Int32 = 0
        /// How many arguments the process was launched with; 0 until read.
        var argumentCount = 0
        /// When the process started and whether a debugger is attached; `nil` until read, or
        /// when the kernel won't say.
        var processStart: ProcessStart?
        /// The memory footprint, in megabytes (MiB).
        var footprintMB: Double = 0
        /// Time since the process started, or `nil` if the kernel didn't say when that was.
        var uptime: TimeInterval?
        /// The network's reachability while a drawer holds the plugin.
        var network = NetworkReachability.unknown
        /// The provisioning profile and the entitlements; none until read.
        var signing = AppSigning(profile: .none, entitlements: nil)
        /// Whether the profile had expired when the facts were last read.
        var isProfileExpired = false

        /// The commit, branch and CI build shown: each one the host passed, or the bundle's.
        var build: AppInfoBuildMetadata {
            buildMetadata.filled(from: bundle.buildMetadata)
        }
    }
#else
    /// Release builds read nothing: this stand-in holds nothing.
    public struct AppInfoSnapshot: Codable, Equatable, Sendable {}
#endif
