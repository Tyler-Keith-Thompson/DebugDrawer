#if DEBUG
    import Foundation

    /// What the app's bundle says about the build: its identifier, version and build number, and
    /// the commit, branch and CI build its Info.plist holds under DebugDrawer's keys.
    struct BundleInfo: Codable, Equatable, Sendable {
        /// `CFBundleIdentifier`, or `nil` when the bundle has none.
        var identifier: String?
        /// `CFBundleShortVersionString`, or `nil`.
        var version: String?
        /// `CFBundleVersion`, or `nil`.
        var build: String?
        /// The commit, branch and CI build under `DebugDrawerGitCommit`, `DebugDrawerGitBranch`
        /// and `DebugDrawerCIBuildNumber`; each `nil` when missing or empty.
        var buildMetadata = AppInfoBuildMetadata()
    }
#endif
