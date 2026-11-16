// Foundation only, and in every build: see FeatureFlagValue.swift.
import Foundation

/// One flag as the app's flag service reports it: its key, how to show it, and its live value.
///
/// The type exists in every build so a ``FeatureFlagProvider`` conformance compiles unchanged in
/// release.
public struct FeatureFlag: Hashable, Sendable {
    /// Identifies the flag to the flag service ("new-checkout").
    public let key: String
    /// What the drawer shows for the flag ("New checkout"); the key when `nil`.
    public let title: String?
    /// A line about what the flag controls, if the service has one.
    public let detail: String?
    /// The value the flag service serves, before any override.
    public let liveValue: FeatureFlagValue

    /// - Parameters:
    ///   - key: Identifies the flag to the flag service.
    ///   - liveValue: The value the flag service serves, before any override.
    ///   - title: What the drawer shows for the flag; the key unless given.
    ///   - detail: A line about what the flag controls.
    public init(key: String, liveValue: FeatureFlagValue, title: String? = nil, detail: String? = nil) {
        self.key = key
        self.liveValue = liveValue
        self.title = title
        self.detail = detail
    }
}
