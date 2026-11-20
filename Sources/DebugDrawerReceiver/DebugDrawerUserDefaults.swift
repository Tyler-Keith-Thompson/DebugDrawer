import Combine
import Foundation
import os

// The allowlisted UserDefaults capability's model (DD-127, charter D9: medium risk). The host lists
// the keys a sidecar may read and edit, each with its kind; nothing else of the domain is read,
// listed or written, so browsing it is impossible by construction: the model never calls
// `dictionaryRepresentation()`, and a command naming any other key is refused `notExposed` before
// the model sees it. A value is read as the key's declared kind only, and written only when the
// kind takes it.
//
// It lives in the receiver rather than in a capability module moved out of the UserDefaults
// plugin: nothing of that plugin is reused. The plugin browses whole domains and edits every
// property-list type (data, dates, arrays, dictionaries), the very things this capability must not
// do, and the audit entry, in the receiver, names this capability's value type, so the value type
// has to live here anyway.
//
// An edit lasts for the session by default (`.session(revertWith: .revertAll)`): a defaults value
// is the app's persistent state, so an edit left behind would go on changing an employee's real
// use of the app long after the session that made it. Before the first edit of a key the model
// records what the key held (the object itself, whatever its kind, or that it held nothing of the
// app's own), in the same defaults under `DebugDrawer.UserDefaults.originalValues`, so the revert
// puts back exactly that, and a launch that follows a kill during a session finds the record and
// reverts as the capability is made. A host whose keys are meant to stay set (a one-time flag a
// tester skips onboarding with) passes `.persistent`; the record then stays until a sidecar sends
// `revertAll`. Rejected: persistent by default (DD-108/DD-267: a session-scoped change outliving
// its session is the bug those items chase), and keeping the record in the receiver's store (the
// model may be made, and shown in the drawer, apart from any receiver, and the record must sit
// beside the values it restores).
//
// Each edit and each revert returns its changes, the key with what it read before and after, which
// the receiver writes to the audit entry (`DebugDrawerAuditEntry.changes`). The values are ones the
// host allowlisted for a sidecar to read, so writing them to the audit log exposes nothing the
// sidecar couldn't already see.

/// The model behind the allowlisted UserDefaults ``DebugDrawerReceiverCapability``: the keys the
/// host lets a sidecar read and edit, their values, and the keys a sidecar edited.
///
/// A debug build can show the same model in its drawer, through
/// `DebugDrawerPluginTransport.direct(to:)`, while the receiver serves it.
@MainActor
public final class DebugDrawerUserDefaults: DebugDrawerPluginModel {
    private static let logger = Logger(subsystem: "DebugDrawerReceiver", category: "DebugDrawerUserDefaults")

    /// The ID the receiver serves it under.
    public static let pluginID = "DebugDrawer.UserDefaults"

    /// An allowlisted key as a sidecar sees it: its declaration and its value now.
    public struct Entry: Codable, Equatable, Sendable {
        /// The UserDefaults key.
        public var key: String
        /// The name a sidecar shows beside the editor.
        public var title: String
        /// The values it holds.
        public var kind: DebugDrawerUserDefaultsKey.Kind
        /// What the app reads for it now, or `nil` when it holds no value of its kind.
        public var value: DebugDrawerUserDefaultsValue?

        /// An entry.
        ///
        /// - Parameters:
        ///   - key: The UserDefaults key.
        ///   - title: The name a sidecar shows.
        ///   - kind: The values it holds.
        ///   - value: What the app reads for it now.
        public init(key: String, title: String, kind: DebugDrawerUserDefaultsKey.Kind, value: DebugDrawerUserDefaultsValue?) {
            self.key = key
            self.title = title
            self.kind = kind
            self.value = value
        }
    }

    /// What a sidecar sees: the allowlisted keys, in the host's order, and nothing else of the
    /// domain.
    public struct Snapshot: Codable, Equatable, Sendable {
        /// The allowlisted keys with their values, in the host's order.
        public var entries: [Entry]
        /// The allowlisted keys a sidecar edited and ``Command/revertAll`` puts back, sorted.
        public var editedKeys: [String]

        /// A snapshot.
        ///
        /// - Parameters:
        ///   - entries: The allowlisted keys with their values.
        ///   - editedKeys: The keys a sidecar edited, sorted.
        public init(entries: [Entry], editedKeys: [String]) {
            self.entries = entries
            self.editedKeys = editedKeys
        }
    }

    /// What a sidecar asks.
    public enum Command: Codable, Equatable, Sendable {
        /// Writes `value` to the allowlisted `key`; the value must be one the key's kind takes.
        case set(key: String, value: DebugDrawerUserDefaultsValue)
        /// Removes the app's value of the allowlisted `key`, so the app reads its registered
        /// default, if any.
        case remove(key: String)
        /// Puts every key a sidecar edited back as it was before its first edit: the session's
        /// revert by default.
        case revertAll
    }

    /// The allowlisted keys and their values now.
    @Published public private(set) var snapshot: Snapshot

    /// The defaults key under which the model records what each key it edited held before.
    nonisolated static let originalValuesDefaultsKey = "DebugDrawer.UserDefaults.originalValues"

    private let keys: [DebugDrawerUserDefaultsKey]
    private let kinds: [String: DebugDrawerUserDefaultsKey.Kind]
    private let defaults: UserDefaults
    private var observation: AnyCancellable?

    /// The allowlisted `keys` of `defaults`: all a sidecar may read and edit.
    ///
    /// Traps when two keys are the same.
    ///
    /// - Parameters:
    ///   - keys: The keys a sidecar may read and edit, in the order to list them; none lists
    ///     nothing.
    ///   - defaults: The defaults the keys are in, where the model also records what each key it
    ///     edits held before.
    public convenience init(_ keys: DebugDrawerUserDefaultsKey..., defaults: UserDefaults = .standard) {
        self.init(keys: keys, defaults: defaults)
    }

    /// The allowlisted keys as a list, for the capability's variadic factory, which can't
    /// forward its own.
    init(keys: [DebugDrawerUserDefaultsKey], defaults: UserDefaults) {
        precondition(Set(keys.map(\.key)).count == keys.count, "An allowlisted UserDefaults key is listed twice")
        self.keys = keys
        kinds = Dictionary(uniqueKeysWithValues: keys.map { ($0.key, $0.kind) })
        self.defaults = defaults
        snapshot = Snapshot(entries: [], editedKeys: [])
        snapshot = currentSnapshot()
        // Any change, as the notification names the instance that wrote and not its suite: two
        // instances of one suite are different objects. Reading the listed keys again is cheap,
        // and the snapshot is published only when it differs.
        observation = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
    }

    /// Reads the allowlisted keys again, for a host that changed them without UserDefaults
    /// noticing; the model already follows UserDefaults' change notifications.
    public func refresh() {
        let current = currentSnapshot()
        if current != snapshot {
            snapshot = current
        }
    }

    /// Why the receiver refuses `command` before the model performs it, or `nil` to perform it: a
    /// key the host didn't allowlist is ``DebugDrawerAuditEntry/Refusal/notExposed``, a value its
    /// kind doesn't take ``DebugDrawerAuditEntry/Refusal/malformedCommand``.
    func refusal(of command: Command) -> DebugDrawerAuditEntry.Refusal? {
        switch command {
        case let .set(key, value):
            guard let kind = kinds[key] else { return .notExposed }
            return kind.accepts(value) ? nil : .malformedCommand
        case let .remove(key):
            return kinds[key] == nil ? .notExposed : nil
        case .revertAll:
            return nil
        }
    }

    /// Does what `command` asks, for an allowlisted key and a value its kind takes only.
    ///
    /// - Parameter command: What to do.
    public func perform(_ command: Command) {
        _ = apply(command)
    }

    /// Does what `command` asks, and returns what it changed: each key with what it read before
    /// and after, for the audit log.
    func apply(_ command: Command) -> [DebugDrawerAuditEntry.Change] {
        defer { refresh() }
        switch command {
        case let .set(key, value):
            guard let kind = kinds[key], kind.accepts(value) else {
                Self.logger.notice("Ignored a value for a key the host didn't allowlist, or one its kind doesn't take")
                return []
            }
            let before = kind.value(of: defaults.object(forKey: key))
            recordOriginal(of: key)
            defaults.set(value.propertyListValue, forKey: key)
            return [DebugDrawerAuditEntry.Change(key: key, oldValue: before, newValue: kind.value(of: defaults.object(forKey: key)))]
        case let .remove(key):
            guard let kind = kinds[key] else {
                Self.logger.notice("Ignored a removal of a key the host didn't allowlist")
                return []
            }
            let before = kind.value(of: defaults.object(forKey: key))
            recordOriginal(of: key)
            defaults.removeObject(forKey: key)
            return [DebugDrawerAuditEntry.Change(key: key, oldValue: before, newValue: kind.value(of: defaults.object(forKey: key)))]
        case .revertAll:
            return revertAll()
        }
    }

    /// Whether the model recorded an original it hasn't put back: an edit since the last revert,
    /// in this launch or an earlier one.
    var hasEdits: Bool {
        !originals.isEmpty
    }

    private func revertAll() -> [DebugDrawerAuditEntry.Change] {
        var changes: [DebugDrawerAuditEntry.Change] = []
        for (key, original) in originals.sorted(by: { $0.key < $1.key }) {
            let kind = kinds[key]
            let before = kind?.value(of: defaults.object(forKey: key))
            if let object = original.first {
                defaults.set(object, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
            // A key recorded by a launch whose allowlist listed it, and this one doesn't, is put
            // back too, but its value isn't read: no kind says what of it may be shown.
            if let kind {
                changes.append(DebugDrawerAuditEntry.Change(key: key, oldValue: before, newValue: kind.value(of: defaults.object(forKey: key))))
            }
        }
        defaults.removeObject(forKey: Self.originalValuesDefaultsKey)
        return changes
    }

    /// Records what `key` holds now, unless an edit since the last revert recorded it already: the
    /// object itself, or an empty list when it holds nothing of the app's own, so the revert
    /// removes it and the app reads its registered default again.
    private func recordOriginal(of key: String) {
        var record = originals
        guard record[key] == nil else { return }
        let object = defaults.object(forKey: key)
        let registered = defaults.volatileDomain(forName: UserDefaults.registrationDomain)[key]
        // The value read may be the registered default rather than one the app wrote: put back by
        // removing the key, the app follows its registered default again.
        let isRegisteredDefault = object.map { ($0 as AnyObject).isEqual(registered) } ?? true
        record[key] = isRegisteredDefault ? [] : object.map { [$0] } ?? []
        defaults.set(record, forKey: Self.originalValuesDefaultsKey)
    }

    /// What each key edited since the last revert held before, by key: a one-object list, or an
    /// empty one for nothing of the app's own.
    private var originals: [String: [Any]] {
        (defaults.dictionary(forKey: Self.originalValuesDefaultsKey) ?? [:]).compactMapValues { $0 as? [Any] }
    }

    private func currentSnapshot() -> Snapshot {
        Snapshot(
            entries: keys.map { Entry(key: $0.key, title: $0.title, kind: $0.kind, value: $0.kind.value(of: defaults.object(forKey: $0.key))) },
            editedKeys: originals.keys.filter { kinds[$0] != nil }.sorted()
        )
    }
}
