import Combine
import Foundation
import os

// The feature flag overrides capability's model. It keeps the keys it overrode itself, so clearing
// (the session's revert) puts back only what a sidecar changed and never an override the host or
// its drawer set. A command naming a key the adapter doesn't list, or a value of another kind than
// the flag's, changes nothing: the adapter's list is the whole of what a sidecar may touch.
// Rejected: refusing such a command in the audit log (the model decoded it, so the session applied
// it; the model is what knows the keys, and it logs what it ignored), and asking the adapter which
// keys are overridden (an adapter over a flag SDK may not know which override came from where).

/// The model behind the feature flag overrides ``DebugDrawerReceiverCapability``: the flags the
/// host's adapter lists, and the overrides a sidecar applied to them.
///
/// A debug build can show the same model in its drawer, through
/// `DebugDrawerPluginTransport.direct(to:)`, while the receiver serves it, so the capability is
/// tested in the process as a sidecar would drive it.
@MainActor
public final class DebugDrawerFeatureFlagOverrides: DebugDrawerPluginModel {
    private static let logger = Logger(subsystem: "DebugDrawerReceiver", category: "DebugDrawerFeatureFlagOverrides")

    /// The ID the receiver serves it under.
    public static let pluginID = "DebugDrawer.FeatureFlagOverrides"

    /// What a sidecar sees.
    public struct Snapshot: Codable, Equatable, Sendable {
        /// The flags the adapter lists, with the values the app reads now.
        public var flags: [DebugDrawerFeatureFlag]
        /// The keys this model overrode, sorted.
        public var overriddenKeys: [String]

        /// A snapshot.
        ///
        /// - Parameters:
        ///   - flags: The flags the adapter lists.
        ///   - overriddenKeys: The keys this model overrode, sorted.
        public init(flags: [DebugDrawerFeatureFlag], overriddenKeys: [String]) {
            self.flags = flags
            self.overriddenKeys = overriddenKeys
        }
    }

    /// What a sidecar asks.
    public enum Command: Codable, Equatable, Sendable {
        /// Overrides the flag `key` with `value`, which must be of the kind the flag has.
        case setOverride(key: String, value: DebugDrawerFeatureFlagValue)
        /// Clears the override this model set on `key`.
        case clearOverride(key: String)
        /// Clears every override this model set: the session's revert by default.
        case clearAllOverrides
    }

    /// The flags and overrides now.
    @Published public private(set) var snapshot: Snapshot

    private let adapter: any DebugDrawerFeatureFlagAdapter
    private var overridden: Set<String> = []

    /// Overrides through `adapter`.
    ///
    /// - Parameter adapter: The host's adapter to its flag service.
    public init(adapter: some DebugDrawerFeatureFlagAdapter) {
        self.adapter = adapter
        snapshot = Snapshot(flags: adapter.overridableFlags(), overriddenKeys: [])
    }

    /// Reads the adapter's flags again, for a host whose flags changed outside the receiver.
    public func refresh() {
        let current = Snapshot(flags: adapter.overridableFlags(), overriddenKeys: overridden.sorted())
        if current != snapshot {
            snapshot = current
        }
    }

    /// Does what `command` asks, for a flag the adapter lists only.
    ///
    /// - Parameter command: What to do.
    public func perform(_ command: Command) {
        switch command {
        case let .setOverride(key, value):
            guard let flag = adapter.overridableFlags().first(where: { $0.key == key }) else {
                Self.logger.notice("Ignored an override of a flag the adapter doesn't list")
                return
            }
            guard flag.value.isSameKind(as: value) else {
                Self.logger.notice("Ignored an override of another kind than the flag's")
                return
            }
            adapter.setOverride(value, forKey: key)
            overridden.insert(key)
        case let .clearOverride(key):
            guard overridden.remove(key) != nil else { return }
            adapter.clearOverride(forKey: key)
        case .clearAllOverrides:
            for key in overridden.sorted() {
                adapter.clearOverride(forKey: key)
            }
            overridden = []
        }
        refresh()
    }
}
