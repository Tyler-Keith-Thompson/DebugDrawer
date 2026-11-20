import Combine
import Foundation
import os

// The experiment overrides capability's model, the feature flag overrides' sibling: it keeps the
// keys it overrode itself (in the defaults, so a relaunch still knows them) and clears only those,
// and a command naming an experiment the adapter doesn't list, or a variant the experiment
// doesn't have, changes nothing and is refused by the receiver before the model sees it
// (`refusal(of:)`). A variant is one of a closed list, so one outside it is malformed rather than
// unexposed, as a tweak's value outside its options is.
//
// What it adds is the analytics exclusion hook, the guard against polluting the experiment's
// data. A host can't miss it three ways: it is a requirement of the adapter, so an adapter that
// doesn't handle it doesn't compile; the adapter hears the state as the model is made (overrides
// a persistent scope kept from the last launch included), not only on a change; and
// `overriddenExperiments` can be read at any time from any thread, behind a lock rather than on
// the main actor because analytics pipelines tag events on their own queues and can't wait for a
// hop. `OSAllocatedUnfairLock` rather than `Mutex`, which needs iOS 18.
// Rejected: an optional callback on the capability (a host could leave it out and never hear it),
// a notification only (missed by an observer that subscribes after launch), and the analytics
// mirror (DebugDrawerAnalytics) marking events itself (it sees only what reaches a sidecar during
// a session, not the host's own analytics service, which is what the experiment's data comes from).

/// The model behind the experiment overrides ``DebugDrawerReceiverCapability``: the experiments the
/// host's adapter lists, the variants a sidecar forced, and whether this device must be left out of
/// the experiments' analytics.
///
/// A debug build can show the same model in its drawer, through
/// `DebugDrawerPluginTransport.direct(to:)`, while the receiver serves it.
@MainActor
public final class DebugDrawerExperimentOverrides: DebugDrawerPluginModel {
    private static let logger = Logger(subsystem: "DebugDrawerReceiver", category: "DebugDrawerExperimentOverrides")

    /// The ID the receiver serves it under.
    public static let pluginID = "DebugDrawer.ExperimentOverrides"

    /// What a sidecar sees.
    public struct Snapshot: Codable, Equatable, Sendable {
        /// The experiments the adapter lists, with the variants the app is assigned now.
        public var experiments: [DebugDrawerExperiment]
        /// The experiments this model overrode, sorted: while any is, the host leaves this device
        /// out of the experiments' analytics.
        public var overriddenKeys: [String]

        /// A snapshot.
        ///
        /// - Parameters:
        ///   - experiments: The experiments the adapter lists.
        ///   - overriddenKeys: The experiments this model overrode, sorted.
        public init(experiments: [DebugDrawerExperiment], overriddenKeys: [String]) {
            self.experiments = experiments
            self.overriddenKeys = overriddenKeys
        }
    }

    /// What a sidecar asks.
    public enum Command: Codable, Equatable, Sendable {
        /// Forces `variant`, one of the experiment's, for the experiment `experiment`.
        case setOverride(experiment: String, variant: String)
        /// Clears the override this model set on `experiment`.
        case clearOverride(experiment: String)
        /// Clears every override this model set: the session's revert by default.
        case clearAllOverrides
    }

    /// The experiments and overrides now.
    @Published public private(set) var snapshot: Snapshot

    /// The experiments this device forces a variant of, sorted, readable from any thread: the
    /// state to tag or drop analytics events by. It holds the overrides kept from the last launch
    /// from the moment the model is made.
    public nonisolated var overriddenExperiments: [String] {
        overriddenNow.withLock { $0 }
    }

    /// Whether this device forces any experiment's variant, so its analytics events must be left
    /// out of the experiments' analysis; readable from any thread.
    public nonisolated var isExcludedFromAnalytics: Bool {
        !overriddenExperiments.isEmpty
    }

    /// The defaults key under which the model keeps the keys it overrode.
    static let overriddenKeysDefaultsKey = "DebugDrawer.ExperimentOverrides.overriddenKeys"

    private let adapter: any DebugDrawerExperimentAdapter
    private let defaults: UserDefaults
    private nonisolated let overriddenNow: OSAllocatedUnfairLock<[String]>
    private var overridden: Set<String> {
        didSet {
            guard overridden != oldValue else { return }
            let keys = overridden.sorted()
            if keys.isEmpty {
                defaults.removeObject(forKey: Self.overriddenKeysDefaultsKey)
            } else {
                defaults.set(keys, forKey: Self.overriddenKeysDefaultsKey)
            }
            overriddenNow.withLock { $0 = keys }
            adapter.overriddenExperimentsDidChange(keys)
        }
    }

    /// Overrides through `adapter`, keeping the keys it overrode in the standard defaults.
    ///
    /// Tells the adapter, before returning, which experiments are overridden now
    /// (``DebugDrawerExperimentAdapter/overriddenExperimentsDidChange(_:)``).
    ///
    /// - Parameter adapter: The host's adapter to its experiment service.
    public convenience init(adapter: some DebugDrawerExperimentAdapter) {
        self.init(adapter: adapter, defaults: .standard)
    }

    /// Overrides through `adapter`, keeping the keys it overrode in `defaults`, so a relaunched
    /// app still lists, reports and clears the overrides a sidecar set before it quit.
    ///
    /// Tells the adapter, before returning, which experiments are overridden now
    /// (``DebugDrawerExperimentAdapter/overriddenExperimentsDidChange(_:)``).
    ///
    /// - Parameters:
    ///   - adapter: The host's adapter to its experiment service.
    ///   - defaults: Where the keys it overrode are kept (never the variants).
    public init(adapter: some DebugDrawerExperimentAdapter, defaults: UserDefaults) {
        self.adapter = adapter
        self.defaults = defaults
        let kept = (defaults.stringArray(forKey: Self.overriddenKeysDefaultsKey) ?? []).sorted()
        overridden = Set(kept)
        overriddenNow = OSAllocatedUnfairLock(initialState: kept)
        snapshot = Snapshot(experiments: adapter.overridableExperiments(), overriddenKeys: kept)
        adapter.overriddenExperimentsDidChange(kept)
    }

    /// Reads the adapter's experiments again, for a host whose assignments changed outside the
    /// receiver.
    public func refresh() {
        let current = Snapshot(experiments: adapter.overridableExperiments(), overriddenKeys: overridden.sorted())
        if current != snapshot {
            snapshot = current
        }
    }

    /// Why the receiver refuses `command` before the model performs it, or `nil` to perform it: an
    /// experiment the adapter doesn't list is ``DebugDrawerAuditEntry/Refusal/notExposed``, a
    /// variant the experiment doesn't have ``DebugDrawerAuditEntry/Refusal/malformedCommand``.
    /// Clearing an experiment the model overrode is never refused, even once the adapter stops
    /// listing it.
    func refusal(of command: Command) -> DebugDrawerAuditEntry.Refusal? {
        switch command {
        case let .setOverride(key, variant):
            guard let experiment = adapter.overridableExperiments().first(where: { $0.key == key }) else { return .notExposed }
            return experiment.variants.contains(variant) ? nil : .malformedCommand
        case let .clearOverride(key):
            guard overridden.contains(key) || adapter.overridableExperiments().contains(where: { $0.key == key }) else { return .notExposed }
            return nil
        case .clearAllOverrides:
            return nil
        }
    }

    /// Does what `command` asks, for an experiment the adapter lists and one of its variants only.
    ///
    /// - Parameter command: What to do.
    public func perform(_ command: Command) {
        switch command {
        case let .setOverride(key, variant):
            guard let experiment = adapter.overridableExperiments().first(where: { $0.key == key }) else {
                Self.logger.notice("Ignored an override of an experiment the adapter doesn't list")
                return
            }
            guard experiment.variants.contains(variant) else {
                Self.logger.notice("Ignored an override with a variant the experiment doesn't have")
                return
            }
            adapter.setOverride(variant: variant, forExperiment: key)
            overridden.insert(key)
        case let .clearOverride(key):
            guard overridden.contains(key) else { return }
            adapter.clearOverride(forExperiment: key)
            overridden.remove(key)
        case .clearAllOverrides:
            for key in overridden.sorted() {
                adapter.clearOverride(forExperiment: key)
            }
            overridden = []
        }
        refresh()
    }
}
