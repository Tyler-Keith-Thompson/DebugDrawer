import CryptoKit
import Foundation
import os

// The payloads the capability keeps for a sidecar, in a directory of the app's own (Application
// Support by default), not in the app group's container: a crash is delivered on a later launch,
// when no session may be open, so it waits here, where only the app reads it, until a session
// opens and the mirror puts it in its snapshot. One JSON file per payload, the newest `capacity`
// kept, plus the fingerprints of the ones a sidecar deleted, as MetricKit hands its past payloads
// to every new subscriber and a deleted one would otherwise come back at the next launch. Main
// actor isolated, as the mirror is: the files are a few, small, written as a payload arrives.

/// The redacted payloads kept for a sidecar, newest first, across launches.
@MainActor
final class MetricKitPayloadArchive {
    private static let logger = Logger(subsystem: "DebugDrawerMetricKit", category: "MetricKitPayloadArchive")
    /// How many deleted payloads' fingerprints are remembered: more than MetricKit holds from the
    /// past.
    static let deletedFingerprintLimit = 200

    let directory: URL
    let capacity: Int
    let maximumPayloadSize: Int
    /// Every payload kept, the latest period first.
    private(set) var payloads: [MetricKitPayloadsMirror.Payload]
    /// The fingerprints of the payloads deleted, oldest first.
    private var deleted: [String]

    /// The payloads kept in `directory`, which is made if missing.
    ///
    /// - Parameters:
    ///   - directory: Where the payloads live.
    ///   - capacity: How many are kept; one more drops the one whose period ended first.
    ///   - maximumPayloadSize: The most bytes a payload's redacted JSON may hold to be kept.
    init(directory: URL, capacity: Int, maximumPayloadSize: Int) {
        self.directory = directory
        self.capacity = capacity
        self.maximumPayloadSize = maximumPayloadSize
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        payloads = files
            .filter { $0.pathExtension == "json" && $0.lastPathComponent != Self.deletedFileName }
            .compactMap { file in (try? Data(contentsOf: file)).flatMap { try? decoder.decode(MetricKitPayloadsMirror.Payload.self, from: $0) } }
            .sorted(by: MetricKitPayloadsMirror.Payload.isNewer)
        deleted = (try? Data(contentsOf: directory.appending(path: Self.deletedFileName)))
            .flatMap { try? decoder.decode([String].self, from: $0) } ?? []
        // A smaller capacity than the last launch's drops the oldest now.
        for dropped in payloads.dropFirst(capacity) {
            removeFile(for: dropped.id)
        }
        payloads = Array(payloads.prefix(capacity))
    }

    /// Keeps each of `received`, redacted by `redaction`, that isn't kept already (the same kind
    /// and redacted JSON) or deleted: JSON that isn't an object is dropped, and so is one larger
    /// than ``maximumPayloadSize`` once redacted, or older than the newest ``capacity``.
    ///
    /// - Parameters:
    ///   - received: The payloads MetricKit delivered.
    ///   - redaction: What to mask before anything is kept.
    ///   - date: When they arrived; also the period of one that names none.
    /// - Returns: Whether the payloads kept changed.
    func receive(_ received: [ReceivedMetricKitPayload], redaction: MetricKitRedaction, at date: Date) -> Bool {
        var added: [MetricKitPayloadsMirror.Payload] = []
        for incoming in received {
            guard let json = redaction.redact(incoming.json) else {
                Self.logger.notice("Dropped a MetricKit payload whose JSON isn't an object")
                continue
            }
            guard json.count <= maximumPayloadSize else {
                let (size, limit) = (json.count, maximumPayloadSize)
                Self.logger.notice("Dropped a MetricKit payload of \(size, privacy: .public) bytes, over the limit of \(limit, privacy: .public)")
                continue
            }
            let isKnown = (payloads + added).contains { $0.kind == incoming.kind && $0.json == json }
            guard !isKnown, !deleted.contains(Self.fingerprint(kind: incoming.kind, json: json)) else { continue }
            added.append(MetricKitPayloadsMirror.Payload(incoming, json: json, received: date))
        }
        guard !added.isEmpty else { return false }
        let sorted = (payloads + added).sorted(by: MetricKitPayloadsMirror.Payload.isNewer)
        let kept = Array(sorted.prefix(capacity))
        let keptIDs = Set(kept.map(\.id))
        for payload in added where keptIDs.contains(payload.id) {
            save(payload)
        }
        for dropped in sorted.dropFirst(capacity) {
            removeFile(for: dropped.id)
        }
        let changed = kept.map(\.id) != payloads.map(\.id)
        payloads = kept
        return changed
    }

    /// Deletes the payloads with `ids`, remembering them so MetricKit can't bring them back.
    ///
    /// - Returns: Whether any was kept.
    func delete(_ ids: Set<UUID>) -> Bool {
        let removed = payloads.filter { ids.contains($0.id) }
        guard !removed.isEmpty else { return false }
        for payload in removed {
            removeFile(for: payload.id)
        }
        deleted = Array((deleted + removed.map { Self.fingerprint(kind: $0.kind, json: $0.json) }).suffix(Self.deletedFingerprintLimit))
        do {
            try JSONEncoder().encode(deleted).write(to: directory.appending(path: Self.deletedFileName), options: .atomic)
        } catch {
            Self.logger.error("Couldn't remember the deleted MetricKit payloads: \(error.localizedDescription, privacy: .public)")
        }
        payloads.removeAll { ids.contains($0.id) }
        return true
    }

    private static let deletedFileName = "deleted.json"

    /// A payload's identity across launches, without its contents.
    private static func fingerprint(kind: MetricKitPayloadKind, json: Data) -> String {
        SHA256.hash(data: Data(kind.rawValue.utf8) + [0] + json).map { String(format: "%02x", $0) }.joined()
    }

    private func save(_ payload: MetricKitPayloadsMirror.Payload) {
        do {
            try JSONEncoder().encode(payload).write(to: file(for: payload.id), options: .atomic)
        } catch {
            Self.logger.error("Couldn't keep a MetricKit payload: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func removeFile(for id: UUID) {
        try? FileManager.default.removeItem(at: file(for: id))
    }

    private func file(for id: UUID) -> URL {
        directory.appending(path: "\(id.uuidString).json")
    }
}

extension MetricKitPayloadsMirror.Payload {
    /// `received` as kept, its JSON already redacted; its period from the sender, else from its
    /// JSON's timestamps, else `date`.
    fileprivate init(_ received: ReceivedMetricKitPayload, json: Data, received date: Date) {
        let object = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any]
        self.init(
            id: UUID(),
            kind: received.kind,
            begin: received.begin ?? Self.timestamp(object?["timeStampBegin"]) ?? date,
            end: received.end ?? Self.timestamp(object?["timeStampEnd"]) ?? date,
            received: date,
            json: json
        )
    }

    // The MetricKit plugin reads timestamps the same way; a few lines repeated rather than a
    // module both depend on for them.
    /// A timestamp as MetricKit writes it (`2025-11-16 00:00:00 +0000`), or in ISO 8601.
    fileprivate static func timestamp(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return formatter.date(from: text) ?? (try? Date(text, strategy: .iso8601))
    }

    /// Whether `first` sorts before `second`: the later period first, then the later arrival, ties
    /// by identity so the order is the same on every load.
    fileprivate static func isNewer(_ first: Self, _ second: Self) -> Bool {
        if first.end != second.end { return first.end > second.end }
        if first.received != second.received { return first.received > second.received }
        return first.id.uuidString < second.id.uuidString
    }
}
