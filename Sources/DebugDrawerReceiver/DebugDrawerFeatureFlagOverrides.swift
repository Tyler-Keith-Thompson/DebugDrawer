import Combine
import Foundation
import os

// The feature flag overrides capability's model. It keeps the keys it overrode itself, so clearing
// (the session's revert) puts back only what a sidecar changed and never an override the host or
// its drawer set. A command naming a key the adapter doesn't list, or a value of another kind than
// the flag's, changes nothing: the adapter's list is the whole of what a sidecar may touch. Through
// the receiver such a command is refused before the model sees it (`refusal(of:)`), so the audit
// log says it changed nothing rather than that it was applied: a sidecar reaching for a flag the
// host didn't mark overridable, a server-enforced one say, is what an auditor looks for. The model
// still ignores it, and logs it, for a caller that isn't the receiver (the drawer's direct
// transport). Rejected: asking the adapter which keys are overridden (an adapter over a flag SDK
// may not know which override came from where).
//
// The keys it overrode are kept in the defaults, as an adapter may keep its overrides across
// launches: so a relaunched app still knows which overrides a sidecar set, lists them, and clears
// them when asked, and a session-scoped capability made at launch clears those a session left
// when the app quit during it (`DebugDrawerReceiverCapability.featureFlagOverrides`). Only keys
// are kept, never values. Rejected: a file in the receiver's store (the model is made, and may be
// shown in the drawer, before and apart from any receiver), and a storage protocol of its own
// (`UserDefaults(suiteName:)` already lets a host or a test keep them apart).

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

    /// The defaults key under which the model keeps the keys it overrode.
    static let overriddenKeysDefaultsKey = "DebugDrawer.FeatureFlagOverrides.overriddenKeys"

    private let adapter: any DebugDrawerFeatureFlagAdapter
    private let defaults: UserDefaults
    private var overridden: Set<String> {
        didSet {
            guard overridden != oldValue else { return }
            if overridden.isEmpty {
                defaults.removeObject(forKey: Self.overriddenKeysDefaultsKey)
            } else {
                defaults.set(overridden.sorted(), forKey: Self.overriddenKeysDefaultsKey)
            }
        }
    }

    /// Overrides through `adapter`, keeping the keys it overrode in the standard defaults.
    ///
    /// - Parameter adapter: The host's adapter to its flag service.
    public convenience init(adapter: some DebugDrawerFeatureFlagAdapter) {
        self.init(adapter: adapter, defaults: .standard)
    }

    /// Overrides through `adapter`, keeping the keys it overrode in `defaults`, so a relaunched
    /// app still lists and clears the overrides a sidecar set before it quit.
    ///
    /// - Parameters:
    ///   - adapter: The host's adapter to its flag service.
    ///   - defaults: Where the keys it overrode are kept (never their values).
    public init(adapter: some DebugDrawerFeatureFlagAdapter, defaults: UserDefaults) {
        self.adapter = adapter
        self.defaults = defaults
        let kept = Set(defaults.stringArray(forKey: Self.overriddenKeysDefaultsKey) ?? [])
        overridden = kept
        snapshot = Snapshot(flags: adapter.overridableFlags(), overriddenKeys: kept.sorted())
    }

    /// Reads the adapter's flags again, for a host whose flags changed outside the receiver.
    public func refresh() {
        let current = Snapshot(flags: adapter.overridableFlags(), overriddenKeys: overridden.sorted())
        if current != snapshot {
            snapshot = current
        }
    }

    /// Why the receiver refuses `command` before the model performs it, or `nil` to perform it: a
    /// flag the adapter doesn't list is ``DebugDrawerAuditEntry/Refusal/notExposed``, a value of
    /// another kind than the flag's ``DebugDrawerAuditEntry/Refusal/malformedCommand``. Clearing a
    /// key the model overrode is never refused, even once the adapter stops listing it.
    func refusal(of command: Command) -> DebugDrawerAuditEntry.Refusal? {
        switch command {
        case let .setOverride(key, value):
            guard let flag = adapter.overridableFlags().first(where: { $0.key == key }) else { return .notExposed }
            return flag.value.isSameKind(as: value) ? nil : .malformedCommand
        case let .clearOverride(key):
            guard overridden.contains(key) || adapter.overridableFlags().contains(where: { $0.key == key }) else { return .notExposed }
            return nil
        case .clearAllOverrides:
            return nil
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
