#if DEBUG
    import Combine
    import Foundation

    /// The payloads kept in a directory, one JSON file each, the newest ``limit`` kept, so the
    /// history survives relaunches.
    ///
    /// The directory is the seam tests replace (a temporary one), as Crash Reports' store does.
    /// Main-actor isolated, like the drawer that shows and edits it.
    @MainActor
    final class MetricKitPayloadStore: ObservableObject {
        /// How many payloads are kept; one more deletes the one whose period ended first. Fifty is
        /// seven weeks of daily metrics with room for diagnostics.
        static let limit = 50

        let directory: URL
        /// Every payload kept, the latest period first.
        @Published private(set) var payloads: [MetricKitPayload] = []
        /// Called with the number of unseen payloads whenever the payloads change.
        private let onUnseenCountChange: @MainActor (Int) -> Void

        /// The payloads kept in `directory`, which is created if missing.
        ///
        /// - Parameters:
        ///   - directory: Where the payloads live.
        ///   - onUnseenCountChange: Called with the number of unseen payloads whenever the
        ///     payloads change: the plugin's badge.
        init(directory: URL, onUnseenCountChange: @escaping @MainActor (Int) -> Void = { _ in }) {
            self.directory = directory
            self.onUnseenCountChange = onUnseenCountChange
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            payloads = Self.load(from: directory)
        }

        /// How many payloads the developer hasn't opened.
        var unseenCount: Int {
            payloads.count { !$0.isSeen }
        }

        /// Keeps each of `received` not kept already (the same kind and JSON), and returns the
        /// ones kept: JSON that isn't an object is dropped, and so is a payload older than the
        /// newest ``limit``.
        ///
        /// - Parameter date: When they arrived; also the period of one that names none.
        @discardableResult
        func receive(_ received: [ReceivedMetricKitPayload], at date: Date = Date()) -> [MetricKitPayload] {
            var added: [MetricKitPayload] = []
            for incoming in received {
                guard let payload = MetricKitPayload(incoming, received: date),
                      !(payloads + added).contains(where: { $0.kind == payload.kind && $0.json == payload.json })
                else { continue }
                added.append(payload)
            }
            guard !added.isEmpty else { return [] }
            let sorted = (payloads + added).sorted(by: MetricKitPayload.isNewer)
            let kept = Array(sorted.prefix(Self.limit))
            let keptIDs = Set(kept.map(\.id))
            for payload in added where keptIDs.contains(payload.id) {
                save(payload)
            }
            for dropped in sorted.dropFirst(Self.limit) {
                try? FileManager.default.removeItem(at: file(for: dropped.id))
            }
            update(kept)
            return added.filter { keptIDs.contains($0.id) }
        }

        /// Marks the payload with `id` as opened.
        func markSeen(_ id: MetricKitPayload.ID) {
            update(payloads.map { payload in
                guard payload.id == id, !payload.isSeen else { return payload }
                var seen = payload
                seen.isSeen = true
                save(seen)
                return seen
            })
        }

        /// Marks every payload as opened.
        func markAllSeen() {
            for payload in payloads where !payload.isSeen {
                markSeen(payload.id)
            }
        }

        /// Deletes the payload with `id`.
        func delete(_ id: MetricKitPayload.ID) {
            try? FileManager.default.removeItem(at: file(for: id))
            update(payloads.filter { $0.id != id })
        }

        /// Deletes every payload.
        func deleteAll() {
            for payload in payloads {
                try? FileManager.default.removeItem(at: file(for: payload.id))
            }
            update([])
        }

        private func update(_ newPayloads: [MetricKitPayload]) {
            payloads = newPayloads
            onUnseenCountChange(unseenCount)
        }

        private func save(_ payload: MetricKitPayload) {
            // A payload of data, dates, a string and a Boolean always encodes.
            if let data = try? JSONEncoder().encode(payload) {
                try? data.write(to: file(for: payload.id), options: .atomic)
            }
        }

        private func file(for id: MetricKitPayload.ID) -> URL {
            directory.appending(path: "\(id.uuidString).json")
        }

        /// The payloads in `directory`, the latest period first; a file that isn't one is skipped.
        private static func load(from directory: URL) -> [MetricKitPayload] {
            let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            return files
                .filter { $0.pathExtension == "json" }
                .compactMap { file in (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(MetricKitPayload.self, from: $0) } }
                .sorted(by: MetricKitPayload.isNewer)
        }
    }

    extension MetricKitPayload {
        /// `received` with its keys sorted, so the same payload delivered twice compares equal, and
        /// its period from the sender, else from its JSON's timestamps, else `date`; `nil` when
        /// its JSON isn't an object.
        fileprivate init?(_ received: ReceivedMetricKitPayload, received date: Date) {
            guard let object = (try? JSONSerialization.jsonObject(with: received.json)) as? [String: Any],
                  let json = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
            else { return nil }
            self.init(
                id: UUID(),
                kind: received.kind,
                begin: received.begin ?? Self.timestamp(object["timeStampBegin"]) ?? date,
                end: received.end ?? Self.timestamp(object["timeStampEnd"]) ?? date,
                received: date,
                json: json,
                isSeen: false
            )
        }

        /// A timestamp as MetricKit writes it (`2025-11-16 00:00:00 +0000`), or in ISO 8601.
        fileprivate static func timestamp(_ value: Any?) -> Date? {
            guard let text = value as? String else { return nil }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
            return formatter.date(from: text) ?? (try? Date(text, strategy: .iso8601))
        }

        /// Whether `first` sorts before `second`: the later period first, then the later arrival,
        /// ties by identity so the order is the same on every load.
        fileprivate static func isNewer(_ first: MetricKitPayload, _ second: MetricKitPayload) -> Bool {
            if first.end != second.end { return first.end > second.end }
            if first.received != second.received { return first.received > second.received }
            return first.id.uuidString < second.id.uuidString
        }
    }
#endif
