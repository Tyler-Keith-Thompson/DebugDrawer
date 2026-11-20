import Combine
import DebugDrawerReceiver
import os

// The tweaks capability's model: the production-safe tweaks the host listed, and their values,
// written through the same store `Tweak.value` reads, so a sidecar's change reaches the app's
// typed accessors and persists in the tweaks' storage like the drawer's. It holds only the tweaks
// marked `.productionSafe()`: the mark on the declaration is where the host decides, and a tweak
// without it is never in a snapshot and never changed, whatever a sidecar sends. A command naming
// a key it doesn't hold is refused as `notExposed`, and a value that isn't one of the tweak's (a
// string for a toggle, a removed option, a number outside a stepper's range) as
// `malformedCommand`, each audited by the sessions, before the model sees it
// (`refusal(of:)`). Rejected: ignoring such a command, as the feature flag overrides do (a sidecar
// probing for unmarked tweaks would leave only `commandApplied` in the audit log), and listing
// unmarked tweaks read-only (their titles and values are what the host chose not to expose).

/// The model behind the receiver's tweaks capability: the production-safe tweaks the host
/// listed, with the values the app reads now, which a sidecar changes within a session.
///
/// Make it through `DebugDrawerReceiverCapability.tweaks(_:storage:scope:)`; a sidecar connects to
/// it under ``pluginID``.
@MainActor
public final class TweaksModel: DebugDrawerPluginModel {
    private static let logger = Logger(subsystem: "DebugDrawerTweaks", category: "TweaksModel")

    /// The ID the receiver serves it under.
    public static let pluginID = "DebugDrawer.Tweaks"

    /// What a sidecar sees.
    public struct Snapshot: Codable, Equatable, Sendable {
        /// The production-safe tweaks, in the order the host listed them.
        public var tweaks: [Entry]

        /// A snapshot.
        ///
        /// - Parameter tweaks: The production-safe tweaks, in the order the host listed them.
        public init(tweaks: [Entry]) {
            self.tweaks = tweaks
        }
    }

    /// One production-safe tweak, as a sidecar sees it.
    public struct Entry: Codable, Equatable, Sendable {
        /// What the drawer shows beside the control.
        public var title: String
        /// Identifies the tweak in a command.
        public var key: String
        /// How the tweak is edited, and the values it takes.
        public var control: TweakControl
        /// The value the tweak reads until it is set, and after a reset.
        public var defaultValue: TweakStoredValue
        /// The value the app reads now.
        public var value: TweakStoredValue

        /// An entry.
        ///
        /// - Parameters:
        ///   - title: What the drawer shows beside the control.
        ///   - key: Identifies the tweak in a command.
        ///   - control: How the tweak is edited.
        ///   - defaultValue: The value the tweak reads until it is set.
        ///   - value: The value the app reads now.
        public init(title: String, key: String, control: TweakControl, defaultValue: TweakStoredValue, value: TweakStoredValue) {
            self.title = title
            self.key = key
            self.control = control
            self.defaultValue = defaultValue
            self.value = value
        }
    }

    /// What a sidecar asks.
    public enum Command: Codable, Equatable, Sendable {
        /// Stores `value` for the production-safe tweak `key`; it must be one of the tweak's
        /// values.
        case setValue(key: String, value: TweakStoredValue)
        /// Resets the production-safe tweak `key` to its default.
        case reset(key: String)
        /// Resets every production-safe tweak to its default; a revert for
        /// `DebugDrawerChangeScope.session(revertWith:)`.
        case resetAll
    }

    /// The production-safe tweaks and their values now.
    @Published public private(set) var snapshot: Snapshot

    private let tweaks: [AnyTweak]
    private let store: TweakStore
    private var following: AnyCancellable?

    /// A model of `tweaks`' production-safe ones, over `store`.
    ///
    /// - Parameters:
    ///   - tweaks: The tweaks the host listed; those not marked production-safe are left out, and
    ///     of two that share a key the first is kept.
    ///   - store: The values, which it offers to the release build's accessors.
    package init(tweaks: [AnyTweak], store: TweakStore) {
        var keys = Set<String>()
        self.tweaks = tweaks.filter { $0.isProductionSafe && keys.insert($0.key).inserted }
        self.store = store
        snapshot = Snapshot(tweaks: [])
        store.offerProductionSafeTweaks()
        snapshot = currentSnapshot()
        // Every change lands in the store, this model's and, in a debug build, the drawer's.
        following = store.changedKeys.sink { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    /// Does what `command` asks, to a production-safe tweak only, with one of its values only.
    ///
    /// - Parameter command: What to do.
    public func perform(_ command: Command) {
        guard refusal(of: command) == nil else {
            Self.logger.notice("Ignored a command for a tweak that isn't offered, or with a value it doesn't take")
            return
        }
        switch command {
        case let .setValue(key, value):
            store.setStoredValue(value, forKey: key)
        case let .reset(key):
            store.setStoredValue(nil, forKey: key)
        case .resetAll:
            store.reset(keys: tweaks.map(\.key))
        }
    }

    /// Why the receiver refuses `command`, or `nil` when the model performs it.
    package func refusal(of command: Command) -> DebugDrawerAuditEntry.Refusal? {
        switch command {
        case let .setValue(key, value):
            guard let tweak = tweaks.first(where: { $0.key == key }) else { return .notExposed }
            return tweak.resolve(value) == value ? nil : .malformedCommand
        case let .reset(key):
            return tweaks.contains { $0.key == key } ? nil : .notExposed
        case .resetAll:
            return nil
        }
    }

    private func refresh() {
        let current = currentSnapshot()
        if current != snapshot {
            snapshot = current
        }
    }

    private func currentSnapshot() -> Snapshot {
        Snapshot(tweaks: tweaks.map { tweak in
            Entry(
                title: tweak.title,
                key: tweak.key,
                control: tweak.control,
                defaultValue: tweak.defaultValue,
                value: tweak.resolve(store.storedValue(forKey: tweak.key))
            )
        })
    }
}
