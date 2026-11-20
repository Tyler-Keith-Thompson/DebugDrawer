import Combine
import Foundation
import os

#if os(macOS)
    import AppKit
#elseif os(watchOS)
    import WatchKit
#elseif canImport(UIKit)
    import UIKit
#endif

// The only DebugDrawer code a release build links (the charter's D6 and D9): the app's end of the
// app-group store, serving a sidecar app the capabilities the host enabled and nothing else. It
// writes the sessions' snapshot and each enabled capability's to the store, and performs the
// commands a sidecar's transport leaves there, as the drawer's debug-build
// `DebugDrawerAppGroupStoreServer` does, over the same files (AppGroupStoreLayout, StoreDocument),
// so a sidecar's `DebugDrawerSidecarTransport` reaches either. It keeps a small loop of its own
// rather than that server's: the server, its registry and `RegistrySession` are debug-only in the
// drawer's module, with stand-ins in release that must stay inert there.
//
// Default-deny: a command to an ID no enabled capability holds is refused, and so is opening a
// session while none is enabled, each logged and audited; a command to an enabled one goes
// through the sessions, which apply it only within an open session. A command decodes into its
// capability's own `Command` type or is refused as malformed: nothing received is run or
// evaluated. A snapshot is what the capability's model put in it, nothing more, and the receiver
// removes, as it starts, every snapshot file that isn't the sessions' or an enabled capability's,
// so a capability enabled in an earlier launch shows nothing once it isn't.
//
// Commands left while the app was not running are performed as it starts, those left while it was
// suspended as it comes back to the foreground, then each as its file lands (DirectoryWatcher).
// The host's gates (ReceiverGates.swift) come before all of that: a command is refused while the
// receiver's or its capability's gate is off, and a gate turned off ends the session or stops the
// capability.
//
// The receiver is handed the group's store and keeps to its own directory in it,
// `apps/<bundle ID>/`, the main bundle's identifier (AppGroupStoreLayout): it reads commands from
// and writes snapshots and its presence to that directory alone, so a command another app's
// sidecar left, or another app's capture data, never reaches it. The bundle ID isn't a parameter,
// so a host can't point its receiver at another app's directory by mistake.
//
// The socket isn't served: a sidecar's transport falls back to the store while no socket answers,
// and a socket server in a production app is more listening surface for no command the store
// can't carry.

/// Serves a sidecar app, over the app group's store, the capabilities the host enables, and
/// nothing else. It links into a release build: no SwiftUI, no interception, no drawer.
///
/// ```swift
/// let sessions = DebugDrawerSessions(maximumDuration: 15 * 60)
/// let receiver = DebugDrawerReceiver(directory: container.appending(path: "DebugDrawer"), sessions: sessions)
/// receiver.enable(.featureFlagOverrides(flagAdapter))
/// try receiver.start()
/// ```
///
/// A sidecar opens a session through ``DebugDrawerSessions/pluginID`` and, within it, drives the
/// enabled capabilities. A command to a capability that isn't enabled, any command while none is,
/// and any command outside a session is refused, logged and written to the sessions' audit log.
/// Sessions made with a ``DebugDrawerGrantPolicy`` also need a signed grant for each session, and
/// one that lists each capability a command is for.
/// Show your own indicator while ``DebugDrawerSessions/snapshot`` is active.
///
/// To turn it off for everyone without a release, give it a gate, ``isAllowed``, backed by your
/// own remote configuration, and call ``reevaluateGates()`` as that configuration changes;
/// ``enable(_:isAllowed:)`` gates one capability the same way.
@MainActor
public final class DebugDrawerReceiver {
    private static let logger = Logger(subsystem: "DebugDrawerReceiver", category: "DebugDrawerReceiver")

    /// The group's store, usually `DebugDrawer` in the app group's container; the receiver keeps
    /// to its own directory in it, ``appDirectory``.
    public let directory: URL
    /// The sessions every command acts within, and their audit log.
    public let sessions: DebugDrawerSessions
    /// The host's gate: while it returns `false`, every command is refused as
    /// ``DebugDrawerAuditEntry/Refusal/receiverDisabled``, a session's opening included, the open
    /// session ends (``DebugDrawerAuditEntry/Ending/disabledByHost``), reverting its session-scoped
    /// changes, and no capability's snapshot is served. Back it with your own remote
    /// configuration, so a leaked sidecar can be shut out without a release.
    ///
    /// The receiver asks it at every command, as it starts, as the app comes to the foreground,
    /// before writing a capability's snapshot, and at ``reevaluateGates()``, which you call as
    /// your configuration changes so an open session ends without waiting for a command. It
    /// returns `true` unless you set it, at ``init(directory:sessions:isAllowed:)`` or later;
    /// setting it asks the new gate at once.
    public var isAllowed: @MainActor () -> Bool {
        didSet { reevaluateGates() }
    }

    var capabilities: [String: DebugDrawerReceiverCapability] = [:]
    /// Writes each served model's snapshots, by ID, while the receiver runs.
    var writing: [String: Task<Void, Never>] = [:]
    private var watcher: DirectoryWatcher?
    private var performing: Task<Void, Never>?
    /// Whether ``performWaitingCommands()`` is running, so a call from within it returns at once.
    private var isPerformingCommands = false
    private var foregroundObservation: (any NSObjectProtocol)?
    /// The gate each capability was enabled with, by ID; one enabled without a gate has none.
    var capabilityGates: [String: @MainActor () -> Bool] = [:]
    /// The capabilities whose snapshots aren't served while a gate is off, by ID.
    var paused: Set<String> = []
    /// The app's presence file, which lists it in a sidecar's app list, while the receiver runs.
    var presence: PresenceAnnouncement?
    /// Who the presence file says the app is, and whose directory of the store the receiver
    /// serves: the main bundle, unless a test names another app.
    package var identity = AppPresence.Identity.of(.main)

    /// The app's own directory in the group's store, `apps/<bundle ID>` in ``directory``, named by
    /// the main bundle's identifier: its presence file, its snapshots and the commands for it.
    /// The receiver reads and writes nothing outside it. A sidecar's transport reads this
    /// directory (`DebugDrawerAppGroupContainer.appDirectory(of:)`).
    public var appDirectory: URL {
        AppGroupStoreLayout.appDirectory(of: identity.bundleIdentifier, inStore: directory)
    }

    /// The app's files in its directory of the store.
    var layout: AppGroupStoreLayout {
        AppGroupStoreLayout(directory: appDirectory)
    }

    /// A receiver of the store in `directory`, gating every command with `sessions`; it serves
    /// once started, and nothing until a capability is enabled.
    ///
    /// - Parameters:
    ///   - directory: The group's store, `DebugDrawer` in the app group's container; the receiver
    ///     serves its own directory in it, ``appDirectory``, made if it doesn't exist.
    ///   - sessions: The sessions every command acts within.
    public init(directory: URL, sessions: DebugDrawerSessions) {
        self.directory = directory
        self.sessions = sessions
        isAllowed = { true }
    }

    /// A receiver of the store in `directory`, gating every command with `sessions` and, before
    /// them, with the host's `isAllowed`; it serves once started, and nothing until a capability
    /// is enabled.
    ///
    /// - Parameters:
    ///   - directory: The group's store, `DebugDrawer` in the app group's container; the receiver
    ///     serves its own directory in it, ``appDirectory``, made if it doesn't exist.
    ///   - sessions: The sessions every command acts within.
    ///   - isAllowed: The host's gate, ``isAllowed``: while it returns `false` the receiver serves
    ///     nothing and refuses everything.
    public convenience init(directory: URL, sessions: DebugDrawerSessions, isAllowed: @escaping @MainActor () -> Bool) {
        self.init(directory: directory, sessions: sessions)
        self.isAllowed = isAllowed
    }

    /// The IDs of the capabilities enabled, sorted.
    public var enabledCapabilities: [String] {
        capabilities.keys.sorted()
    }

    /// Whether the receiver is writing snapshots and performing commands.
    public var isRunning: Bool {
        watcher != nil
    }

    /// Lets a sidecar read `capability` and, within a session, drive it, in place of any capability
    /// enabled under its ID before.
    ///
    /// - Parameter capability: What to allow.
    public func enable(_ capability: DebugDrawerReceiverCapability) {
        enable(capability, gate: nil)
    }

    /// Stops serving the capability enabled under `id`: its snapshot leaves the store, and its
    /// commands are refused from now on. A change it made in the open session is still reverted as
    /// the session ends. Does nothing when no capability is enabled under `id`.
    ///
    /// - Parameter id: The capability's ID.
    public func disable(_ id: String) {
        guard capabilities.removeValue(forKey: id) != nil else { return }
        capabilityGates[id] = nil
        paused.remove(id)
        writing.removeValue(forKey: id)?.cancel()
        try? FileManager.default.removeItem(at: layout.snapshotFile(for: id))
        presence?.update(capabilities: servedIDs)
    }

    /// Writes the sessions' and each enabled capability's snapshot, performs the commands waiting in
    /// the store, and goes on doing both as they change, and as the app comes back to the
    /// foreground, all in the app's own directory of the store, ``appDirectory``. It also keeps a
    /// presence file there, the app's bundle ID, name, version and build, the IDs it serves and
    /// the protocol version it speaks, so a sidecar built on `DebugDrawerSidecarKit` lists the
    /// app. Does nothing while the receiver runs.
    ///
    /// - Throws: ``DebugDrawerReceiverError/cannotServe`` when the store's directories can't be
    ///   made or watched.
    public func start() throws(DebugDrawerReceiverError) {
        guard watcher == nil else { return }
        let layout = layout
        guard layout.create(), let watcher = DirectoryWatcher(directory: layout.commands) else { throw .cannotServe }
        layout.removeCutOffSnapshots()
        removeSnapshotsNotServed()
        self.watcher = watcher
        serve(DebugDrawerSessions.pluginID, encodedSnapshots(of: sessions))
        paused = []
        for (id, capability) in capabilities {
            serve(id, capability.snapshots())
        }
        // Before any of those writes runs: they wait for the main actor. It performs the commands
        // left while the receiver was stopped first, each in the session it was sent in.
        reevaluateGates()
        performing = Task { [weak self] in
            for await _ in watcher.changes {
                self?.performWaitingCommands()
            }
        }
        // No queue, so the commands are performed before the post returns. The system posts it on
        // the main thread.
        foregroundObservation = NotificationCenter.default.addObserver(forName: Self.foreground, object: nil, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated {
                // The commands waiting first, then the gates: reevaluateGates() does both.
                self?.reevaluateGates()
            }
        }
        presence = PresenceAnnouncement(directory: appDirectory, identity: identity, capabilities: servedIDs, foreground: Self.foreground)
    }

    /// Stops writing snapshots and performing commands. The snapshots written stay in the store, and
    /// commands left meanwhile wait for the next start; the app's presence file goes, so a
    /// sidecar no longer lists it.
    public func stop() {
        presence?.withdraw()
        presence = nil
        if let foregroundObservation {
            NotificationCenter.default.removeObserver(foregroundObservation)
        }
        foregroundObservation = nil
        for task in writing.values {
            task.cancel()
        }
        writing = [:]
        watcher?.cancel()
        watcher = nil
        performing?.cancel()
        performing = nil
    }

    /// Performs each command file in the store, oldest first, removing it first so it runs once.
    /// ``reevaluateGates()`` calls it before it asks the gates, so a host that re-evaluates them
    /// from a capability's command reaches it while it runs, and leaves the rest to it.
    func performWaitingCommands() {
        guard isRunning, !isPerformingCommands else { return }
        isPerformingCommands = true
        defer { isPerformingCommands = false }
        for file in layout.messageFiles(in: layout.commands) {
            let data = try? Data(contentsOf: file)
            do {
                try FileManager.default.removeItem(at: file)
            } catch {
                Self.logger.error("Couldn't remove a command file, so it wasn't performed: \(error.localizedDescription, privacy: .public)")
                continue
            }
            guard let data, let document = StoreDocument.decoded(from: data) else {
                Self.logger.notice("Dropped a command file this build can't read")
                continue
            }
            guard document.isReadable else {
                let version = document.writer.version
                Self.logger.notice("Dropped a command file from protocol version \(version, privacy: .public), which this build doesn't speak")
                continue
            }
            guard document.message.kind == .command else {
                let kind = document.message.kind.name
                Self.logger.debug("Ignored a \(kind, privacy: .public) left in the store")
                continue
            }
            perform(document.message.payload, for: document.message.pluginID)
        }
    }

    /// Performs the command `payload` encodes on the capability `id` names, if one is enabled
    /// there, within the sessions.
    private func perform(_ payload: Data, for id: String) {
        guard gateRefusal(id) == nil else { return }
        guard id != DebugDrawerSessions.pluginID else {
            // A session with nothing to drive would show the host's indicator for nothing.
            guard !capabilities.isEmpty else {
                Self.logger.notice("Refused a session: no capability is enabled")
                sessions.refuse(id, .unknownCapability)
                return
            }
            guard let command = try? JSONDecoder().decode(DebugDrawerSessionCommand.self, from: payload) else {
                sessions.refuse(id, .malformedCommand)
                return
            }
            sessions.perform(command)
            return
        }
        guard let capability = capabilities[id] else {
            Self.logger.notice("Refused a command for \(id, privacy: .public): no capability is enabled under it")
            sessions.refuse(id, .unknownCapability)
            return
        }
        sessions.apply(to: id, scope: capability.scope, requiresGrant: capability.requiresGrant) { capability.perform(payload) }
    }

    /// Applies `change`, a change the host asked for itself rather than a sidecar's command (a bug
    /// report it triggered), to the capability `id` names, through the gates and the sessions as a
    /// sidecar's command goes, and audited the same way: refused while a gate is off, while the
    /// capability isn't enabled, outside a session, or without a grant listing it where one is
    /// needed, and its session-scoped change reverted as the session ends.
    ///
    /// - Returns: Why it was refused, or `nil` when it was applied.
    func applyHostChange(to id: String, _ change: () -> DebugDrawerAuditEntry.Refusal?) -> DebugDrawerAuditEntry.Refusal? {
        if let refusal = gateRefusal(id) {
            return refusal
        }
        guard let capability = capabilities[id] else {
            Self.logger.notice("Refused the host's change to \(id, privacy: .public): no capability is enabled under it")
            sessions.refuse(id, .unknownCapability)
            return .unknownCapability
        }
        return sessions.apply(to: id, scope: capability.scope, requiresGrant: capability.requiresGrant, change)
    }

    /// Writes the snapshots `snapshots` delivers to `id`'s file, in place of any written for it
    /// before.
    func serve(_ id: String, _ snapshots: AsyncStream<Data>) {
        writing[id]?.cancel()
        let layout = layout
        let file = layout.snapshotFile(for: id)
        writing[id] = Task { [weak self] in
            for await payload in snapshots {
                // A gate turned off since the receiver last asked: stop now rather than write, once
                // the commands waiting are performed in their session (reevaluateGates()).
                guard let self, servesSnapshot(of: id) else {
                    self?.reevaluateGates()
                    return
                }
                let document = StoreDocument(TransportMessage(kind: .snapshot, pluginID: id, payload: payload))
                do {
                    try layout.write(document.encoded(), to: file)
                } catch {
                    Self.logger.error("Couldn't write \(id, privacy: .public)'s snapshot: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    /// The IDs the presence file lists: the sessions' and each enabled capability's whose gate is
    /// on, or none while the receiver's gate is off, so a sidecar shows the app as turned off.
    var servedIDs: [String] {
        guard isAllowed() else { return [] }
        return [DebugDrawerSessions.pluginID] + capabilities.keys.filter { !paused.contains($0) }
    }

    /// Removes every snapshot file that is neither the sessions' nor an enabled capability's.
    private func removeSnapshotsNotServed() {
        let served = Set(([DebugDrawerSessions.pluginID] + capabilities.keys).map { layout.snapshotFile(for: $0).lastPathComponent })
        for file in layout.messageFiles(in: layout.snapshots) where !served.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// What the system posts as the app comes to the foreground: on the Mac, where apps aren't
    /// suspended, as it becomes active.
    static var foreground: Notification.Name {
        #if os(macOS)
            NSApplication.willBecomeActiveNotification
        #elseif os(watchOS)
            WKApplication.willEnterForegroundNotification
        #else
            // Mac Catalyst takes this branch too: a Catalyst app is a UIKit app, and UIKit posts it
            // there.
            UIApplication.willEnterForegroundNotification
        #endif
    }
}
