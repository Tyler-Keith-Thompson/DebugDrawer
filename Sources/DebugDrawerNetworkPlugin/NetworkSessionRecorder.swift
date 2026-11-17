#if DEBUG
    import DebugDrawer
    import Foundation
    import os

    /// Writes the current session's requests to a ``NetworkSessionStorage`` as they complete, and
    /// keeps the sessions within ``NetworkSessionPersistence``'s limits; lists, reads and deletes
    /// the sessions earlier launches kept.
    ///
    /// Recording returns at once: a request joins a bounded queue of pending ones under a lock, and
    /// the first to join an empty queue schedules one drain on a serial dispatch queue, which
    /// redacts, encodes and appends every request pending in one write, then looks again, until
    /// none is left. So the URL protocol and the main actor never wait on the disk, a burst of
    /// requests costs one write per turn of the drain rather than one each, and no timer batches
    /// them. Every storage call runs on that queue, so a list or a delete sees every request
    /// recorded before it. A serial queue rather than an actor: tasks hopping to an actor run in
    /// no set order, and their number has no bound.
    final class NetworkSessionRecorder: Sendable {
        /// What is waiting to be written.
        enum Record: Sendable {
            /// A request that completed, and the request it resends, when it is a replay and the
            /// log still holds it.
            case request(NetworkEntry, original: NetworkEntry?)
            /// A WebSocket connection that ended.
            case webSocket(NetworkWebSocketConnection)
        }

        /// The records waiting, oldest first, each with the rules to redact it by, and whether a
        /// drain is scheduled or running.
        private struct Pending {
            var records: [(record: Record, redaction: DebugDrawerRedaction)] = []
            var isDraining = false
        }

        private static let logger = Logger(subsystem: "DebugDrawerNetworkPlugin", category: "NetworkSessionRecorder")

        let persistence: NetworkSessionPersistence
        /// The current session's name in the storage.
        let currentName: String
        /// The most records waiting at once; the oldest goes when another joins a full queue.
        let capacity: Int
        private let header: NetworkSessionHeader
        private let queue = DispatchQueue(label: "DebugDrawerNetworkPlugin.NetworkSessionRecorder")
        private let pending = OSAllocatedUnfairLock(initialState: Pending())

        /// Starts a session and, on the recorder's queue, deletes the sessions earlier launches
        /// kept beyond `persistence`'s limits.
        ///
        /// - Parameters:
        ///   - persistence: Where the sessions are kept, and how many.
        ///   - started: When the current session starts, which names it.
        ///   - id: What makes its name unique.
        ///   - bundle: The app, named in the session's header.
        ///   - capacity: The most records waiting to be written at once.
        init(
            _ persistence: NetworkSessionPersistence,
            started: Date = Date(),
            id: UUID = UUID(),
            bundle: Bundle = .main,
            capacity: Int = 200
        ) {
            self.persistence = persistence
            currentName = NetworkSessionSummary.name(started: started, id: id)
            self.capacity = capacity
            header = NetworkSessionHeader(started: started, bundle: bundle)
            queue.async { [self] in
                pruneEarlierSessions(making: 0, in: listFiles())
            }
        }

        /// Writes `entry`, a request that completed, masked as `redaction` says, soon after; it
        /// returns at once. `original` is the request it resends, if it is a replay.
        func record(_ entry: NetworkEntry, original: NetworkEntry?, redaction: DebugDrawerRedaction) {
            enqueue(.request(entry, original: original), redaction: redaction)
        }

        /// Writes `connection`, a WebSocket connection that ended, masked as `redaction` says,
        /// soon after; it returns at once.
        func record(_ connection: NetworkWebSocketConnection, redaction: DebugDrawerRedaction) {
            enqueue(.webSocket(connection), redaction: redaction)
        }

        /// The sessions earlier launches kept, the newest first, once every record before the
        /// call is written.
        func previousSessions() async -> [NetworkSessionSummary] {
            await onQueue { [self] in
                listFiles()
                    .filter { $0.name != currentName }
                    .compactMap(NetworkSessionSummary.init)
                    .sorted { $0.id > $1.id }
            }
        }

        /// The session `summary` names, read whole.
        ///
        /// - Throws: What the storage throws when it can't read the session.
        func log(of summary: NetworkSessionSummary) async throws -> NetworkSessionLog {
            try await onQueue { [self] () throws -> NetworkSessionLog in
                try NetworkSessionLog(summary: summary, data: persistence.storage.contents(ofSessionNamed: summary.id))
            }
        }

        /// The newest session an earlier launch kept, read on the caller's thread rather than the
        /// recorder's queue, for a bug report the caller builds now; `nil` when there is none or it
        /// can't be read. Earlier sessions are never written to, so reading one beside the queue
        /// is safe.
        func newestPreviousSession() -> NetworkSessionLog? {
            let newest = listFiles()
                .filter { $0.name != currentName }
                .compactMap(NetworkSessionSummary.init)
                .max { $0.id < $1.id }
            guard let newest, let data = try? persistence.storage.contents(ofSessionNamed: newest.id) else { return nil }
            return NetworkSessionLog(summary: newest, data: data)
        }

        /// Deletes the earlier sessions with `ids`; the current session is never deleted.
        func delete(_ ids: [NetworkSessionSummary.ID]) async {
            await onQueue { [self] in
                for id in ids where id != currentName {
                    delete(named: id)
                }
            }
        }

        private func enqueue(_ record: Record, redaction: DebugDrawerRedaction) {
            guard persistence.isOn else { return }
            let schedules = pending.withLock { pending in
                pending.records.append((record, redaction))
                if pending.records.count > capacity {
                    pending.records.removeFirst(pending.records.count - capacity)
                }
                defer { pending.isDraining = true }
                return !pending.isDraining
            }
            if schedules {
                queue.async { [self] in drain() }
            }
        }

        /// Writes what is pending, batch by batch, until nothing is; then the next record schedules
        /// another drain.
        private func drain() {
            while true {
                let batch = pending.withLock { pending -> [(record: Record, redaction: DebugDrawerRedaction)] in
                    defer { pending.records.removeAll() }
                    if pending.records.isEmpty { pending.isDraining = false }
                    return pending.records
                }
                guard !batch.isEmpty else { return }
                write(batch.compactMap { Self.line($0.record, redaction: $0.redaction) })
            }
        }

        /// Appends `lines` to the current session, after its header when the file is new, having
        /// deleted the oldest earlier sessions for room. A line that would take the current
        /// session past `maxBytes` alone isn't written; a smaller one after it still is.
        private func write(_ lines: [Data]) {
            guard !lines.isEmpty else { return }
            let files = listFiles()
            let currentBytes = files.first { $0.name == currentName }?.byteCount ?? 0
            let headerLine = currentBytes == 0 ? Self.line(header) ?? Data() : Data()
            let earlierBytes = pruneEarlierSessions(making: currentBytes + headerLine.count + lines.reduce(0) { $0 + $1.count }, in: files)
            var room = persistence.maxBytes - earlierBytes - currentBytes - headerLine.count
            var fitting = Data()
            for line in lines {
                guard line.count <= room else {
                    Self.logger.notice("A request wasn't kept: the network session is at its size limit")
                    continue
                }
                room -= line.count
                fitting.append(line)
            }
            // A header alone says nothing; it is written only with a request after it.
            guard !fitting.isEmpty else { return }
            fitting.insert(contentsOf: headerLine, at: 0)
            do {
                try persistence.storage.append(fitting, toSessionNamed: currentName)
            } catch {
                Self.logger.error("Network session not written: \(error.localizedDescription, privacy: .public)")
            }
        }

        /// Deletes the oldest earlier sessions beyond `maxSessions`, then the oldest until they
        /// and `bytes` more fit in `maxBytes`, and returns how many bytes the ones kept hold.
        @discardableResult
        private func pruneEarlierSessions(making bytes: Int, in files: [NetworkSessionFile]) -> Int {
            // Oldest first: names start with the session's start.
            var earlier = files
                .filter { $0.name != currentName && NetworkSessionSummary($0) != nil }
                .sorted { $0.name < $1.name }
            let surplus = max(earlier.count - persistence.maxSessions, 0)
            for file in earlier.prefix(surplus) {
                delete(named: file.name)
            }
            earlier.removeFirst(surplus)
            var total = earlier.reduce(bytes) { $0 + $1.byteCount }
            while total > persistence.maxBytes, let oldest = earlier.first {
                delete(named: oldest.name)
                earlier.removeFirst()
                total -= oldest.byteCount
            }
            return earlier.reduce(0) { $0 + $1.byteCount }
        }

        private func listFiles() -> [NetworkSessionFile] {
            do {
                return try persistence.storage.sessionFiles()
            } catch {
                Self.logger.error("Network sessions not listed: \(error.localizedDescription, privacy: .public)")
                return []
            }
        }

        private func delete(named name: String) {
            do {
                try persistence.storage.deleteSession(named: name)
            } catch {
                Self.logger.error("Network session not deleted: \(error.localizedDescription, privacy: .public)")
            }
        }

        private func onQueue<Value: Sendable>(_ body: @escaping @Sendable () -> Value) async -> Value {
            await withCheckedContinuation { continuation in
                queue.async { continuation.resume(returning: body()) }
            }
        }

        private func onQueue<Value: Sendable>(_ body: @escaping @Sendable () throws -> Value) async throws -> Value {
            try await withCheckedThrowingContinuation { continuation in
                queue.async { continuation.resume(with: Result(catching: body)) }
            }
        }
    }

    extension NetworkSessionRecorder {
        /// `record` as one line of the session's file: its archive entry, masked as `redaction`
        /// says, as compact JSON, then a newline.
        fileprivate static func line(_ record: Record, redaction: DebugDrawerRedaction) -> Data? {
            switch record {
            case let .request(entry, original):
                line(HTTPArchive.Entry(entry, original: original, redaction: redaction))
            case let .webSocket(connection):
                line(HTTPArchive.Entry(connection, redaction: redaction))
            }
        }

        /// `value` as compact JSON with sorted keys, then a newline. JSON escapes the newlines in
        /// strings, so the line holds none of its own.
        fileprivate static func line(_ value: some Encodable) -> Data? {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            guard var data = try? encoder.encode(value) else { return nil }
            data.append(UInt8(ascii: "\n"))
            return data
        }
    }
#endif
