import DebugDrawerReceiver
import Foundation

// The standard fields (the bundle's identity, version and build, the build's metadata and when it
// was read) are always there; every other field is optional, `nil` unless the host registered its
// source, and synthesized encoding leaves a `nil` out, so a host that registers nothing serves
// nothing but the build. Overrides, experiments and values are keyed by name, so the report's
// JSON reads `"new-checkout": true` and the sidecar's redaction masks a value by its key.

extension DebugDrawerAppState {
    /// An experiment as the app's state shows it: its bucket, and whether a sidecar forced it.
    public struct ExperimentBucket: Codable, Equatable, Sendable {
        /// The variant the app is in now, the experiment's bucket; `nil` when not enrolled.
        public var variant: String?
        /// Whether a sidecar's override put the app in it.
        public var isOverridden: Bool

        /// An experiment's bucket.
        ///
        /// - Parameters:
        ///   - variant: The variant the app is in now, or `nil`.
        ///   - isOverridden: Whether a sidecar's override put the app in it.
        public init(variant: String?, isOverridden: Bool) {
            self.variant = variant
            self.isOverridden = isOverridden
        }
    }

    /// The backend the app is pointed at, as the environments capability says it.
    public struct ActiveEnvironment: Codable, Equatable, Sendable {
        /// The active environment's ID.
        public var id: String
        /// The active environment's title.
        public var title: String
        /// Whether it is another than the app's default, during a sidecar's session.
        public var isSwitched: Bool

        /// The active environment.
        ///
        /// - Parameters:
        ///   - id: Its ID.
        ///   - title: Its title.
        ///   - isSwitched: Whether it is another than the app's default.
        public init(id: String, title: String, isSwitched: Bool) {
            self.id = id
            self.title = title
            self.isSwitched = isSwitched
        }
    }

    /// The app's state as read once: the build always, and each field the host registered.
    public struct State: Codable, Equatable, Sendable {
        /// The app's bundle identifier.
        public var bundleIdentifier: String
        /// `CFBundleShortVersionString`, or empty.
        public var version: String
        /// `CFBundleVersion`, or empty.
        public var build: String
        /// The commit, branch and CI build the build came from, those the host or its Info.plist
        /// name.
        public var buildMetadata: AppInfoBuildMetadata
        /// When it was read.
        public var date: Date

        /// The flags a sidecar overrides now, by key, with their values; `nil` unless the host
        /// registered its feature flag overrides.
        public var featureFlagOverrides: [String: DebugDrawerFeatureFlagValue]?
        /// Every experiment the host lists, by key, with its bucket; `nil` unless the host
        /// registered its experiment overrides.
        public var experiments: [String: ExperimentBucket]?
        /// The backend the app is pointed at; `nil` unless the host registered its environments.
        public var environment: ActiveEnvironment?
        /// The signed-in user's ID, hashed in the process with the install's own key; `nil`
        /// unless the host registered a user ID, and while it reads none.
        public var hashedUserID: String?
        /// The host's own values, by key; `nil` unless the host registered fields.
        public var values: [String: DebugDrawerAppStateValue]?

        /// A reading of the app's state.
        ///
        /// - Parameters:
        ///   - bundleIdentifier: The app's bundle identifier.
        ///   - version: `CFBundleShortVersionString`.
        ///   - build: `CFBundleVersion`.
        ///   - buildMetadata: The commit, branch and CI build.
        ///   - date: When it was read.
        ///   - featureFlagOverrides: The flags overridden now, or `nil`.
        ///   - experiments: The experiments and their buckets, or `nil`.
        ///   - environment: The active environment, or `nil`.
        ///   - hashedUserID: The hashed user ID, or `nil`.
        ///   - values: The host's values, or `nil`.
        public init(
            bundleIdentifier: String,
            version: String,
            build: String,
            buildMetadata: AppInfoBuildMetadata,
            date: Date,
            featureFlagOverrides: [String: DebugDrawerFeatureFlagValue]? = nil,
            experiments: [String: ExperimentBucket]? = nil,
            environment: ActiveEnvironment? = nil,
            hashedUserID: String? = nil,
            values: [String: DebugDrawerAppStateValue]? = nil
        ) {
            self.bundleIdentifier = bundleIdentifier
            self.version = version
            self.build = build
            self.buildMetadata = buildMetadata
            self.date = date
            self.featureFlagOverrides = featureFlagOverrides
            self.experiments = experiments
            self.environment = environment
            self.hashedUserID = hashedUserID
            self.values = values
        }
    }
}
