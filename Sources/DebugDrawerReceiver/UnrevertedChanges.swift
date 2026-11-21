import Foundation
import os

// The receiver's record of the session-scoped changes it owes a revert, kept in the app's own
// directory of the store (`unreverted-changes.json`), so that a launch killed during a session
// leaves the next launch a list of what to put back. Sessions live in memory: without this, a
// change whose session never ended (the app quit or was killed during it) would outlive the
// session for good wherever the change itself persists (a tweak's stored value, a model of the
// app's own that keeps its state).
//
// One entry per capability and session, the capability's ID and the session's: the ID is what the
// next launch reverts, the session is what its audit entry names, and both are all the record
// holds (no command, no value). The file is written before the change it covers is made and
// removed after the revert runs, so a kill between any two steps leaves at worst one revert too
// many, which does nothing (a capability's revert puts back what is left, and nothing is), never a
// change without its entry. Written as the store writes, through a partial file renamed over it.
//
// What a launch before this one left is read once, as the record is first used, and kept apart
// from the entries this launch adds: only those are reverted as their capability is enabled, so a
// capability disabled and enabled again during a session isn't reverted under it.
//
// Rejected: the app's own defaults (the receiver takes no defaults, only its directory, where
// a test or a second receiver already keeps apart from another; the store's writers can add or
// remove an entry, but what they can do with one, make the next launch put a capability back or
// skip doing so, is less than what they can do with a command), and a field in the sessions'
// snapshot (a sidecar reads that, and the receiver rewrites it from memory at every start).

/// The capabilities whose session-scoped changes are still owed a revert, by session, in a file of
/// the app's directory of the store.
@MainActor
final class UnrevertedChanges {
    private static let logger = Logger(subsystem: "DebugDrawerReceiver", category: "UnrevertedChanges")

    /// The record's name in the app's directory of the store.
    static let fileName = "unreverted-changes.json"

    /// One capability's change in one session, not yet reverted.
    struct Entry: Codable, Equatable {
        /// The ID the capability is enabled under.
        let capability: String
        /// The session the change was made in.
        let sessionID: UUID
    }

    /// The file's contents.
    private struct Contents: Codable {
        var changes: [Entry]
    }

    /// Where the record is kept.
    let file: URL
    /// Every entry the file holds now, in the order each was added.
    private(set) var entries: [Entry]
    /// The entries a launch before this one left, by capability: those its revert is owed for once
    /// the capability is enabled.
    private var left: [String: UUID]

    /// The record in `file`, with what a launch before this one left there.
    init(file: URL) {
        self.file = file
        let entries: [Entry]
        if let data = try? Data(contentsOf: file) {
            do {
                entries = try JSONDecoder().decode(Contents.self, from: data).changes
            } catch {
                // Unreadable is as good as empty: it can't say what to revert. The next write
                // replaces it.
                Self.logger.error("Couldn't read the record of unreverted session changes: \(error.localizedDescription, privacy: .public)")
                entries = []
            }
        } else {
            entries = []
        }
        self.entries = entries
        left = Dictionary(entries.map { ($0.capability, $0.sessionID) }) { first, _ in first }
    }

    /// Whether the record holds `capability`'s change in session `sessionID`.
    func contains(_ capability: String, in sessionID: UUID) -> Bool {
        entries.contains(Entry(capability: capability, sessionID: sessionID))
    }

    /// Adds `capability`'s change in session `sessionID` and writes the record.
    func insert(_ capability: String, in sessionID: UUID) {
        let entry = Entry(capability: capability, sessionID: sessionID)
        guard !entries.contains(entry) else { return }
        entries.append(entry)
        write()
    }

    /// Removes `capability`'s change in session `sessionID`, if the record holds it, and writes the
    /// record.
    func remove(_ capability: String, in sessionID: UUID) {
        let entry = Entry(capability: capability, sessionID: sessionID)
        guard entries.contains(entry) else { return }
        entries.removeAll { $0 == entry }
        if left[capability] == sessionID {
            left[capability] = nil
        }
        write()
    }

    /// Removes every change made in session `sessionID` and writes the record.
    func removeAll(in sessionID: UUID) {
        guard entries.contains(where: { $0.sessionID == sessionID }) else { return }
        entries.removeAll { $0.sessionID == sessionID }
        left = left.filter { $0.value != sessionID }
        write()
    }

    /// The session in which a launch before this one changed `capability` without reverting it, or
    /// `nil`; asked once, as the capability is enabled. The entry stays until the revert removes it.
    func takeLeft(_ capability: String) -> UUID? {
        left.removeValue(forKey: capability)
    }

    /// Writes the entries, or removes the file once there are none.
    private func write() {
        do {
            guard !entries.isEmpty else {
                if FileManager.default.fileExists(atPath: file.path) {
                    try FileManager.default.removeItem(at: file)
                }
                return
            }
            let directory = file.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try AppGroupStoreLayout(directory: directory).write(encoder.encode(Contents(changes: entries)), to: file)
        } catch {
            // The change goes ahead, as it would have without the record: a store the receiver
            // can't write serves a sidecar no snapshot either, and no refusal says why to one.
            Self.logger.error("Couldn't write the record of unreverted session changes: \(error.localizedDescription, privacy: .public)")
        }
    }
}
