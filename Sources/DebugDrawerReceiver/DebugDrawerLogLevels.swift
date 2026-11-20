import Combine
import Foundation
import os

// The log levels capability's model, the feature flag and experiment overrides' sibling: it keeps
// the subsystems it raised itself (in the defaults, so a relaunch still knows them) and resets only
// those, and a command naming a subsystem the adapter doesn't list, or a level the subsystem
// doesn't list, changes nothing and is refused by the receiver before the model sees it
// (`refusal(of:)`). A level is one of a closed list, so one outside it is malformed rather than
// unexposed, as an experiment's variant outside its list is.
//
// It lives in the receiver rather than in a capability module re-exported by the Console plugin:
// modules.py's capability modules are a plugin's UI-free half, and nothing of the Console's is
// needed here (the level is the host logger's, set through the adapter; the Console's capture and
// its OSLogClient dependency stay debug-only). Rejected: a DebugDrawerConsole capability module
// (it would hold no Console code, only this model, under the Console's name), a closed level enum
// (loggers name and order their levels differently, and a host maps its own), and a persistent
// scope (verbose lines left on after the session would keep writing what nobody asked for).

/// The model behind the log levels ``DebugDrawerReceiverCapability``: the subsystems the host's
/// adapter lists, with their levels, and those a sidecar raised.
///
/// A debug build can show the same model in its drawer, through
/// `DebugDrawerPluginTransport.direct(to:)`, while the receiver serves it.
@MainActor
public final class DebugDrawerLogLevels: DebugDrawerPluginModel {
    private static let logger = Logger(subsystem: "DebugDrawerReceiver", category: "DebugDrawerLogLevels")

    /// The ID the receiver serves it under.
    public static let pluginID = "DebugDrawer.LogLevels"

    /// What a sidecar sees.
    public struct Snapshot: Codable, Equatable, Sendable {
        /// The subsystems the adapter lists, with the level each logs at now.
        public var subsystems: [DebugDrawerLogSubsystem]
        /// The subsystems this model raised, sorted: each is reset as the session ends.
        public var raisedSubsystems: [String]

        /// A snapshot.
        ///
        /// - Parameters:
        ///   - subsystems: The subsystems the adapter lists.
        ///   - raisedSubsystems: The subsystems this model raised, sorted.
        public init(subsystems: [DebugDrawerLogSubsystem], raisedSubsystems: [String]) {
            self.subsystems = subsystems
            self.raisedSubsystems = raisedSubsystems
        }
    }

    /// What a sidecar asks.
    public enum Command: Codable, Equatable, Sendable {
        /// Sets `subsystem` to `level`, one of the levels the adapter lists for it.
        case setLevel(subsystem: String, level: String)
        /// Resets `subsystem`, if this model raised it.
        case reset(subsystem: String)
        /// Resets every subsystem this model raised: the session's revert.
        case resetAll
    }

    /// The subsystems and their levels now.
    @Published public private(set) var snapshot: Snapshot

    /// The defaults key under which the model keeps the subsystems it raised.
    static let raisedSubsystemsDefaultsKey = "DebugDrawer.LogLevels.raisedSubsystems"

    private let adapter: any DebugDrawerLogLevelAdapter
    private let defaults: UserDefaults
    private var raised: Set<String> {
        didSet {
            guard raised != oldValue else { return }
            if raised.isEmpty {
                defaults.removeObject(forKey: Self.raisedSubsystemsDefaultsKey)
            } else {
                defaults.set(raised.sorted(), forKey: Self.raisedSubsystemsDefaultsKey)
            }
        }
    }

    /// Raises levels through `adapter`, keeping the subsystems it raised in the standard defaults.
    ///
    /// - Parameter adapter: The host's adapter to its logger.
    public convenience init(adapter: some DebugDrawerLogLevelAdapter) {
        self.init(adapter: adapter, defaults: .standard)
    }

    /// Raises levels through `adapter`, keeping the subsystems it raised in `defaults`, so a
    /// relaunched app still resets the levels a session raised before the app quit.
    ///
    /// - Parameters:
    ///   - adapter: The host's adapter to its logger.
    ///   - defaults: Where the subsystems it raised are kept (never their levels).
    public init(adapter: some DebugDrawerLogLevelAdapter, defaults: UserDefaults) {
        self.adapter = adapter
        self.defaults = defaults
        let kept = (defaults.stringArray(forKey: Self.raisedSubsystemsDefaultsKey) ?? []).sorted()
        raised = Set(kept)
        snapshot = Snapshot(subsystems: adapter.elevatableSubsystems(), raisedSubsystems: kept)
    }

    /// Reads the adapter's subsystems again, for a host whose levels changed outside the receiver.
    public func refresh() {
        let current = Snapshot(subsystems: adapter.elevatableSubsystems(), raisedSubsystems: raised.sorted())
        if current != snapshot {
            snapshot = current
        }
    }

    /// Why the receiver refuses `command` before the model performs it, or `nil` to perform it: a
    /// subsystem the adapter doesn't list is ``DebugDrawerAuditEntry/Refusal/notExposed``, a level
    /// the subsystem doesn't list ``DebugDrawerAuditEntry/Refusal/malformedCommand``. Resetting a
    /// subsystem the model raised is never refused, even once the adapter stops listing it.
    func refusal(of command: Command) -> DebugDrawerAuditEntry.Refusal? {
        switch command {
        case let .setLevel(name, level):
            guard let subsystem = adapter.elevatableSubsystems().first(where: { $0.name == name }) else { return .notExposed }
            return subsystem.levels.contains(level) ? nil : .malformedCommand
        case let .reset(name):
            guard raised.contains(name) || adapter.elevatableSubsystems().contains(where: { $0.name == name }) else { return .notExposed }
            return nil
        case .resetAll:
            return nil
        }
    }

    /// Does what `command` asks, for a subsystem the adapter lists and one of its levels only.
    ///
    /// - Parameter command: What to do.
    public func perform(_ command: Command) {
        switch command {
        case let .setLevel(name, level):
            guard let subsystem = adapter.elevatableSubsystems().first(where: { $0.name == name }) else {
                Self.logger.notice("Ignored a level for a subsystem the adapter doesn't list")
                return
            }
            guard subsystem.levels.contains(level) else {
                Self.logger.notice("Ignored a level the subsystem doesn't list")
                return
            }
            adapter.setLevel(level, forSubsystem: name)
            raised.insert(name)
        case let .reset(name):
            guard raised.contains(name) else { return }
            adapter.resetLevel(forSubsystem: name)
            raised.remove(name)
        case .resetAll:
            for name in raised.sorted() {
                adapter.resetLevel(forSubsystem: name)
            }
            raised = []
        }
        refresh()
    }
}
