import Foundation

/// What says which build this is beyond its version: the commit it was built from, the branch and
/// the CI build number. App Info shows them in its Build section, and puts them in Copy Info's
/// text and the bug report.
///
/// Each value is the one passed here or, when that is `nil`, the string under its key in the main
/// bundle's Info.plist, so a CI script can write them into the plist without touching code:
///
/// | Value | Info.plist key |
/// |---|---|
/// | ``gitCommit`` | `DebugDrawerGitCommit` |
/// | ``gitBranch`` | `DebugDrawerGitBranch` |
/// | ``ciBuildNumber`` | `DebugDrawerCIBuildNumber` |
///
/// ```swift
/// DebugDrawer.shared.installAppInfo(buildMetadata: AppInfoBuildMetadata(gitCommit: "4f9c2e1", gitBranch: "release/2.4"))
/// ```
///
/// The type exists in every build, so a value made outside `#if DEBUG` compiles unchanged in
/// release, where nothing reads it.
public struct AppInfoBuildMetadata: Equatable, Sendable {
    /// The commit the build was made from, such as a git SHA; `nil` to read `DebugDrawerGitCommit`.
    public var gitCommit: String?
    /// The branch the build was made from; `nil` to read `DebugDrawerGitBranch`.
    public var gitBranch: String?
    /// The CI system's number for the build; `nil` to read `DebugDrawerCIBuildNumber`.
    public var ciBuildNumber: String?

    /// - Parameters:
    ///   - gitCommit: The commit the build was made from; `nil` to read it from Info.plist.
    ///   - gitBranch: The branch the build was made from; `nil` to read it from Info.plist.
    ///   - ciBuildNumber: The CI system's number for the build; `nil` to read it from Info.plist.
    public init(gitCommit: String? = nil, gitBranch: String? = nil, ciBuildNumber: String? = nil) {
        self.gitCommit = gitCommit
        self.gitBranch = gitBranch
        self.ciBuildNumber = ciBuildNumber
    }
}

#if DEBUG
    extension AppInfoBuildMetadata {
        static let gitCommitKey = "DebugDrawerGitCommit"
        static let gitBranchKey = "DebugDrawerGitBranch"
        static let ciBuildNumberKey = "DebugDrawerCIBuildNumber"

        /// These values, each one that is `nil` read from `info`, an Info.plist's dictionary.
        func filled(from info: [String: Any]?) -> AppInfoBuildMetadata {
            AppInfoBuildMetadata(
                gitCommit: gitCommit ?? info.string(forKey: Self.gitCommitKey),
                gitBranch: gitBranch ?? info.string(forKey: Self.gitBranchKey),
                ciBuildNumber: ciBuildNumber ?? info.string(forKey: Self.ciBuildNumberKey)
            )
        }
    }

    extension [String: Any]? {
        /// The non-empty string under `key`; a build setting left unset in a CI script writes an
        /// empty one, which says no more than a missing key.
        fileprivate func string(forKey key: String) -> String? {
            (self?[key] as? String).flatMap { $0.isEmpty ? nil : $0 }
        }
    }
#endif
