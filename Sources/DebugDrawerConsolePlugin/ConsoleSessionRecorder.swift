#if DEBUG
    import Foundation
    import os

    /// Writes the current session's log lines to a ``ConsoleSessionStorage`` as they are captured,
    /// and keeps the sessions within ``ConsoleSessionPersistence``'s limits; lists, reads and
    /// deletes the sessions earlier launches kept.
    ///
    /// Recording returns at once: a line joins a bounded queue of pending ones under a lock, and
    /// the first to join an empty queue schedules one drain on a serial dispatch queue, which
    /// encodes and appends every line pending in one write, then looks again, until none is left.
    /// So the main actor never waits on the disk, a burst of lines costs one write per turn of the
    /// drain rather than one each, and no timer batches them. Every storage call runs on that
    /// queue, so a list or a delete sees every line recorded before it. A serial queue rather than
    /// an actor: tasks hopping to an actor run in no set order, and their number has no bound.
    final class ConsoleSessionRecorder: Sendable {
        /// A failure the recorder logs once a session at most: the Console captures the app's own
        /// os_log, so a failure logged each time it happens would be captured, written, and logged
        /// again for as long as the app runs.
        private enum Issue: Hashable {
            case full, notWritten, notListed, notDeleted
        }

        /// The lines waiting, oldest first, whether a drain is scheduled or running, and the
        /// issues logged already.
        private struct Pending {
            var lines: [LogLine] = []
            var isDraining = false
            var logged: Set<Issue> = []
        }

        private static let logger = Logger(subsystem: "DebugDrawerConsolePlugin", category: "ConsoleSessionRecorder")

        let persistence: ConsoleSessionPersistence
        /// The current session's name in the storage.
        let currentName: String
        /// The most lines waiting at once; the oldest goes when another joins a full queue.
        let capacity: Int
        private let header: ConsoleSessionHeader
        private let queue = DispatchQueue(label: "DebugDrawerConsolePlugin.ConsoleSessionRecorder")
        private let pending = OSAllocatedUnfairLock(initialState: Pending())

        /// Starts a session and, on the recorder's queue, deletes the sessions earlier launches
        /// kept beyond `persistence`'s limits.
        ///
        /// - Parameters:
        ///   - persistence: Where the sessions are kept, and how many.
        ///   - started: When the current session starts, which names it.
        ///   - id: What makes its name unique.
        ///   - bundle: The app, named in the session's header.
        ///   - capacity: The most lines waiting to be written at once; as many as the console
        ///     holds by default.
        init(
            _ persistence: ConsoleSessionPersistence,
            started: Date = Date(),
            id: UUID = UUID(),
            bundle: Bundle = .main,
            capacity: Int = 2_000
        ) {
            self.persistence = persistence
            currentName = ConsoleSessionSummary.name(started: started, id: id)
            self.capacity = capacity
            header = ConsoleSessionHeader(started: started, bundle: bundle)
            queue.async { [self] in
                pruneEarlierSessions(making: 0, in: listFiles())
            }
        }

        /// Writes `line` soon after; it returns at once.
        func record(_ line: LogLine) {
            guard persistence.isOn else { return }
            let schedules = pending.withLock { pending in
                pending.lines.append(line)
                if pending.lines.count > capacity {
                    pending.lines.removeFirst(pending.lines.count - capacity)
                }
                defer { pending.isDraining = true }
                return !pending.isDraining
            }
            if schedules {
                queue.async { [self] in drain() }
            }
        }

        /// The sessions earlier launches kept, the newest first, once every line before the call
        /// is written.
        func previousSessions() async -> [ConsoleSessionSummary] {
            await onQueue { [self] in
                listFiles()
                    .filter { $0.name != currentName }
                    .compactMap(ConsoleSessionSummary.init)
                    .sorted { $0.id > $1.id }
            }
        }

        /// The session `summary` names, read whole.
        ///
        /// - Throws: What the storage throws when it can't read the session.
        func log(of summary: ConsoleSessionSummary) async throws -> ConsoleSessionLog {
            try await onQueue { [self] () throws -> ConsoleSessionLog in
                try ConsoleSessionLog(summary: summary, data: persistence.storage.contents(ofSessionNamed: summary.id))
            }
        }

        /// The newest session an earlier launch kept, read on the caller's thread rather than the
        /// recorder's queue, for a bug report the caller builds now; `nil` when there is none or it
        /// can't be read. Earlier sessions are never written to, so reading one beside the queue
        /// is safe.
        func newestPreviousSession() -> ConsoleSessionLog? {
            let newest = listFiles()
                .filter { $0.name != currentName }
                .compactMap(ConsoleSessionSummary.init)
                .max { $0.id < $1.id }
            guard let newest, let data = try? persistence.storage.contents(ofSessionNamed: newest.id) else { return nil }
            return ConsoleSessionLog(summary: newest, data: data)
        }

        /// Deletes the earlier sessions with `ids`; the current session is never deleted.
        func delete(_ ids: [ConsoleSessionSummary.ID]) async {
            await onQueue { [self] in
                for id in ids where id != currentName {
                    delete(named: id)
                }
            }
        }

        /// Writes what is pending, batch by batch, until nothing is; then the next line schedules
        /// another drain.
        private func drain() {
            while true {
                let batch = pending.withLock { pending -> [LogLine] in
                    defer { pending.lines.removeAll() }
                    if pending.lines.isEmpty { pending.isDraining = false }
                    return pending.lines
                }
                guard !batch.isEmpty else { return }
                write(batch.compactMap { Self.line(ConsoleSessionLine($0)) })
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
                    logOnce(.full) { Self.logger.notice("Log lines weren't kept: the console session is at its size limit") }
                    continue
                }
                room -= line.count
                fitting.append(line)
            }
            // A header alone says nothing; it is written only with a line after it.
            guard !fitting.isEmpty else { return }
            fitting.insert(contentsOf: headerLine, at: 0)
            do {
                try persistence.storage.append(fitting, toSessionNamed: currentName)
            } catch {
                logOnce(.notWritten) { Self.logger.error("Console session not written: \(error.localizedDescription, privacy: .public)") }
            }
        }

        /// Deletes the oldest earlier sessions beyond `maxSessions`, then the oldest until they
        /// and `bytes` more fit in `maxBytes`, and returns how many bytes the ones kept hold.
        @discardableResult
        private func pruneEarlierSessions(making bytes: Int, in files: [ConsoleSessionFile]) -> Int {
            // Oldest first: names start with the session's start.
            var earlier = files
                .filter { $0.name != currentName && ConsoleSessionSummary($0) != nil }
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

        private func listFiles() -> [ConsoleSessionFile] {
            do {
                return try persistence.storage.sessionFiles()
            } catch {
                logOnce(.notListed) { Self.logger.error("Console sessions not listed: \(error.localizedDescription, privacy: .public)") }
                return []
            }
        }

        private func delete(named name: String) {
            do {
                try persistence.storage.deleteSession(named: name)
            } catch {
                logOnce(.notDeleted) { Self.logger.error("Console session not deleted: \(error.localizedDescription, privacy: .public)") }
            }
        }

        /// Runs `log` the first time `issue` happens this session.
        private func logOnce(_ issue: Issue, _ log: () -> Void) {
            if pending.withLock({ $0.logged.insert(issue).inserted }) {
                log()
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

    extension ConsoleSessionRecorder {
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
